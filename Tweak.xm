#import <UIKit/UIKit.h>
#import <substrate.h>
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <Speech/Speech.h>
#import <AVFoundation/AVFoundation.h>

#define OPENAI_API_KEY @"sk-proj-_"
#define OPENAI_API_URL @"https://api.openai.com/v1/chat/completions"

#define SALOG_HOST "192.168.0.12"
#define SALOG_PORT 5005

static UIImage* captureScreenshot(void);
static void processPromptWithOpenAI(NSString *prompt, UIImage *screenshot);
static void sendTouchEventsToView(CGPoint point, UIView *view);
static void parseCoordinatesAndTouch(NSString *aiResponse, CGSize screenshotSize);

void SALog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[iosAgent] %@", message);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) return;
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(SALOG_PORT);
        inet_pton(AF_INET, SALOG_HOST, &addr.sin_addr);
        
        NSString *logMessage = [NSString stringWithFormat:@"SALOG:%@", message];
        const char *data = [logMessage UTF8String];
        
        sendto(sock, data, strlen(data), 0, (struct sockaddr*)&addr, sizeof(addr));
        close(sock);
    });
}

static BOOL hasInitialized = NO;

@interface OverlayWindow : UIWindow
@property (nonatomic, weak) UIButton *recordButton;
@end

@implementation OverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.recordButton && !self.recordButton.hidden && self.recordButton.userInteractionEnabled) {
        CGPoint converted = [self.recordButton convertPoint:point fromView:self];
        if ([self.recordButton pointInside:converted withEvent:event]) {
            return self.recordButton;
        }
    }
    return nil;
}

@end

@class ButtonVoiceListener;
@class FloatingButtonManager;

@interface ButtonVoiceListener : NSObject <AVAudioRecorderDelegate>
+ (instancetype)shared;
- (void)startRecording;
- (void)stopRecording;
- (void)updateButtonWithText:(NSString *)text;
- (void)updateButtonWithError:(NSString *)error;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) SFSpeechRecognizer *speechRecognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (nonatomic, strong) SFSpeechRecognitionTask *recognitionTask;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSTimer *processingTimer;
@property (nonatomic, copy) NSString *currentTranscription;
@end

@interface FloatingButton : UIView
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL isRecording;
- (void)show;
- (void)hide;
@end

@interface FloatingButtonManager : NSObject
+ (instancetype)shared;
- (void)showFloatingButton;
- (void)hideFloatingButton;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) FloatingButton *floatingButton;
@end

@implementation FloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
        _isRecording = NO;
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.layer.cornerRadius = 25;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowRadius = 10;
    self.layer.shadowOpacity = 0.3;
    
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recordButton.frame = CGRectMake(10, 10, 30, 30);
    self.recordButton.backgroundColor = [UIColor redColor];
    self.recordButton.layer.cornerRadius = 15;
    [self.recordButton setTitle:@"🎤" forState:UIControlStateNormal];
    [self.recordButton addTarget:self action:@selector(recordButtonPressed:) forControlEvents:UIControlEventTouchDown];
    [self.recordButton addTarget:self action:@selector(recordButtonReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self addSubview:self.recordButton];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 10, 200, 30)];
    self.statusLabel.text = @"Press & Hold";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:11];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.adjustsFontSizeToFitWidth = YES;
    self.statusLabel.minimumScaleFactor = 0.7;
    [self addSubview:self.statusLabel];
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panGesture];
}

- (void)recordButtonPressed:(UIButton *)sender {
    if (self.isRecording) return;
    
    SALog(@"[FloatingButton] Record button pressed - Starting recording");
    self.isRecording = YES;
    self.statusLabel.text = @"Recording...";
    self.recordButton.backgroundColor = [UIColor greenColor];
    
    [[ButtonVoiceListener shared] startRecording];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformMakeScale(1.1, 1.1);
    }];
}

- (void)recordButtonReleased:(UIButton *)sender {
    if (!self.isRecording) return;
    
    SALog(@"[FloatingButton] Record button released - Stopping recording");
    self.isRecording = NO;
    self.statusLabel.text = @"Processing...";
    self.recordButton.backgroundColor = [UIColor orangeColor];
    
    [[ButtonVoiceListener shared] stopRecording];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"Press & Hold";
            self.recordButton.backgroundColor = [UIColor redColor];
        });
    }];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat halfWidth = self.frame.size.width / 2;
    CGFloat halfHeight = self.frame.size.height / 2;
    
    if (self.center.x < halfWidth) self.center = CGPointMake(halfWidth, self.center.y);
    if (self.center.x > screenBounds.size.width - halfWidth) self.center = CGPointMake(screenBounds.size.width - halfWidth, self.center.y);
    if (self.center.y < halfHeight + 44) self.center = CGPointMake(self.center.x, halfHeight + 44);
    if (self.center.y > screenBounds.size.height - halfHeight - 34) self.center = CGPointMake(self.center.x, screenBounds.size.height - halfHeight - 34);
}

- (void)show {
    self.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)hide {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end

@implementation ButtonVoiceListener

+ (instancetype)shared {
    static ButtonVoiceListener *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ButtonVoiceListener alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isRecording = NO;
        _currentTranscription = @"";
        [self setupSpeechRecognizer];
        [self requestPermissions];
    }
    return self;
}

- (void)setupSpeechRecognizer {
    NSLocale *locale = [NSLocale currentLocale];
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    self.audioEngine = [[AVAudioEngine alloc] init];
    SALog(@"[ButtonVoice] Speech recognizer and audio engine setup complete");
}

- (void)cleanupAudioResources {
    SALog(@"[ButtonVoice] Cleaning up audio resources...");
    if (self.audioEngine && self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }
    if (self.audioEngine && self.audioEngine.inputNode) {
        @try {
            [self.audioEngine.inputNode removeTapOnBus:0];
        } @catch (NSException *e) {
            SALog(@"[ButtonVoice] Exception removing tap: %@", e.reason);
        }
    }
    if (self.recognitionTask) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }
    if (self.recognitionRequest) {
        [self.recognitionRequest endAudio];
        self.recognitionRequest = nil;
    }
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        SALog(@"[ButtonVoice] Audio session deactivation error: %@", error.localizedDescription);
    }
}

- (void)requestPermissions {
    SALog(@"[ButtonVoice] Requesting permissions...");
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                SALog(@"[ButtonVoice] Speech recognition AUTHORIZED");
                break;
            case SFSpeechRecognizerAuthorizationStatusDenied:
                SALog(@"[ButtonVoice] Speech recognition DENIED");
                break;
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                SALog(@"[ButtonVoice] Speech recognition RESTRICTED");
                break;
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                SALog(@"[ButtonVoice] Speech recognition NOT DETERMINED");
                break;
        }
    }];
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        SALog(@"[ButtonVoice] Microphone permission: %@", granted ? @"GRANTED" : @"DENIED");
    }];
}

- (void)startRecording {
    if (self.isRecording) {
        SALog(@"[ButtonVoice] Already recording, ignoring start request");
        return;
    }
    SALog(@"[ButtonVoice] Starting speech recognition...");
    self.isRecording = YES;
    self.currentTranscription = @"";
    [self cleanupAudioResources];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self actualStartRecording];
    });
}

- (void)actualStartRecording {
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                      mode:AVAudioSessionModeMeasurement
                   options:AVAudioSessionCategoryOptionDefaultToSpeaker |
                          AVAudioSessionCategoryOptionAllowBluetooth |
                          AVAudioSessionCategoryOptionMixWithOthers
                     error:&error];
    if (error) {
        SALog(@"[ButtonVoice] Category setting error: %@", error.localizedDescription);
        [self updateButtonWithError:@"Audio Setup Failed"];
        return;
    }
    error = nil;
    BOOL activated = [audioSession setActive:YES error:&error];
    if (!activated || error) {
        SALog(@"[ButtonVoice] Activation error: %@", error.localizedDescription);
        [self updateButtonWithError:@"Audio Activation Failed"];
        return;
    }
    error = nil;
    AVAudioSessionPortDescription *port = [[audioSession.availableInputs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"portType = %@", AVAudioSessionPortBuiltInMic]] firstObject];
    if (port) {
        [audioSession setPreferredInput:port error:&error];
    }
    self.audioEngine = [[AVAudioEngine alloc] init];
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    if (!self.recognitionRequest) {
        SALog(@"[ButtonVoice] Failed to create recognition request");
        [self updateButtonWithError:@"Recognition Setup Failed"];
        return;
    }
    self.recognitionRequest.shouldReportPartialResults = YES;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult *result, NSError *taskError) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (taskError && taskError.code != 216) {
            SALog(@"[ButtonVoice] Recognition error: %@", taskError.localizedDescription);
            [self updateButtonWithError:[NSString stringWithFormat:@"Error: %@", taskError.localizedDescription]];
            return;
        }
        if (result) {
            self.currentTranscription = result.bestTranscription.formattedString;
            [self updateButtonWithText:self.currentTranscription];
            SALog(@"[ButtonVoice] Live transcription: \"%@\" (Final: %@)",
                  self.currentTranscription,
                  result.isFinal ? @"YES" : @"NO");
        }
    });
}];
    if (!self.recognitionTask) {
        SALog(@"[ButtonVoice] Failed to create recognition task");
        [self updateButtonWithError:@"Recognition Task Failed"];
        return;
    }
    AVAudioInputNode *inputNode = self.audioEngine.inputNode;
    if (!inputNode) {
        SALog(@"[ButtonVoice] Audio input node not available");
        [self updateButtonWithError:@"Microphone Not Available"];
        return;
    }
    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        if (self.recognitionRequest) {
            [self.recognitionRequest appendAudioPCMBuffer:buffer];
        }
    }];
    [self.audioEngine prepare];
    BOOL started = [self.audioEngine startAndReturnError:&error];
    if (!started || error) {
        SALog(@"[ButtonVoice] Audio engine start error: %@", error.localizedDescription);
        [self updateButtonWithError:@"Recording Failed"];
        return;
    }
    SALog(@"[ButtonVoice] Recording started successfully");
    [self updateButtonWithText:@"Listening..."];
}

- (void)stopRecording {
    if (!self.isRecording) return;
    SALog(@"[ButtonVoice] Stopping recording...");
    self.isRecording = NO;
    if (self.processingTimer) {
        [self.processingTimer invalidate];
        self.processingTimer = nil;
    }
    self.processingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(processDelayedTranscription)
                                                        userInfo:nil
                                                         repeats:NO];
    [self cleanupAudioResources];
    SALog(@"[ButtonVoice] Recording stopped and cleanup completed");
}

- (void)dealloc {
    if (self.processingTimer) {
        [self.processingTimer invalidate];
        self.processingTimer = nil;
    }
}


- (void)processDelayedTranscription {
    if (self.currentTranscription && self.currentTranscription.length > 0) {
        SALog(@"[ButtonVoice] Processing final transcription after delay: \"%@\"",
              self.currentTranscription);
        [self processTranscription:self.currentTranscription];
    } else {
        SALog(@"[ButtonVoice] No transcription to process after delay");
        [self updateButtonWithError:@"No speech detected"];
    }
}

- (void)processTranscription:(NSString *)transcription {
    if (!transcription || transcription.length == 0) {
        SALog(@"[ButtonVoice] Empty transcription, ignoring");
        [self updateButtonWithError:@"No speech detected"];
        return;
    }
    
    SALog(@"[ButtonVoice] Processing transcription: \"%@\"", transcription);
    [self updateButtonWithText:[NSString stringWithFormat:@"Processing: %@", transcription]];
    
    UIImage *screenshot = captureScreenshot();
    NSLog(@"Screenshot size: %.0f x %.0f, scale: %.1f",screenshot.size.width, screenshot.size.height, screenshot.scale);
    if (screenshot) {
        SALog(@"[ButtonVoice] Screenshot captured, sending to OpenAI...");
        processPromptWithOpenAI(transcription, screenshot);
    } else {
        SALog(@"[ButtonVoice] Failed to capture screenshot");
        [self updateButtonWithError:@"Screenshot failed"];
    }
}

- (void)updateButtonWithText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        FloatingButtonManager *manager = [FloatingButtonManager shared];
        if (manager.floatingButton) {
            manager.floatingButton.statusLabel.text = text;
            SALog(@"[ButtonVoice] Button text updated: %@", text);
        }
    });
}

- (void)updateButtonWithError:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        FloatingButtonManager *manager = [FloatingButtonManager shared];
        if (manager.floatingButton) {
            manager.floatingButton.statusLabel.text = error;
            manager.floatingButton.recordButton.backgroundColor = [UIColor orangeColor];
            SALog(@"[ButtonVoice] Button error updated: %@", error);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                manager.floatingButton.statusLabel.text = @"Press & Hold";
                manager.floatingButton.recordButton.backgroundColor = [UIColor redColor];
            });
        }
    });
}

@end

@implementation FloatingButtonManager

+ (instancetype)shared {
    static FloatingButtonManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FloatingButtonManager alloc] init];
    });
    return shared;
}

- (void)showFloatingButton {
    SALog(@"[FloatingManager] Showing floating button...");
    
    if (self.overlayWindow) {
        [self hideFloatingButton];
    }
    
    self.overlayWindow = [[OverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.hidden = NO;
    
    self.floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 100, 250, 50)];
    [self.overlayWindow addSubview:self.floatingButton];
    
    ((OverlayWindow *)self.overlayWindow).recordButton = self.floatingButton.recordButton;
    
    [self.floatingButton show];
    SALog(@"[FloatingManager] Floating button shown");
}

- (void)hideFloatingButton {
    SALog(@"[FloatingManager] Hiding floating button...");
    
    if (self.floatingButton) {
        [self.floatingButton hide];
        self.floatingButton = nil;
    }
    
    if (self.overlayWindow) {
        self.overlayWindow.hidden = YES;
        self.overlayWindow = nil;
    }
    
    SALog(@"[FloatingManager] Floating button hidden");
}

@end

static UIImage* captureScreenshot() {
    SALog(@"[Screenshot] Starting screenshot capture...");
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.windowLevel == UIWindowLevelNormal && !window.isHidden) {
            keyWindow = window;
            break;
        }
    }
    
    if (keyWindow) {
        SALog(@"[Screenshot] Capturing from window: %@", keyWindow);
        UIGraphicsBeginImageContextWithOptions(keyWindow.bounds.size, NO, 0.0);
        [keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:YES];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        SALog(@"[Screenshot] Screenshot captured successfully");
        return img;
    }
    
    SALog(@"[Screenshot] Failed to capture screenshot");
    return nil;
}

static void performFakeTouch(CGPoint point) {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGPoint pointInPoints = CGPointMake(point.x / scale, point.y / scale);
    
    SALog(@"[Touch] Performing touch at pixels(%.1f, %.1f) -> points(%.1f, %.1f)",
          point.x, point.y, pointInPoints.x, pointInPoints.y);
    
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *keyWindow = nil;
    
    for (UIWindow *window in app.windows) {
        if (window.windowLevel == UIWindowLevelNormal && !window.isHidden &&
            ![window isKindOfClass:[OverlayWindow class]]) {
            keyWindow = window;
            break;
        }
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
        SALog(@"[Touch] Using keyWindow: %@", keyWindow);
    }
    
    if (!keyWindow) {
        SALog(@"[Touch] No valid window found for touch");
        return;
    }
    
    UIView *hitView = [keyWindow hitTest:pointInPoints withEvent:nil];
    SALog(@"[Touch] Hit view: %@ at point (%.1f, %.1f)", hitView, pointInPoints.x, pointInPoints.y);
    
    UIView *flashView = [[UIView alloc] initWithFrame:CGRectMake(pointInPoints.x-10, pointInPoints.y-10, 20, 20)];
    flashView.backgroundColor = [UIColor greenColor];
    flashView.layer.cornerRadius = 10;
    flashView.alpha = 0.8;
    [keyWindow addSubview:flashView];
    
    [UIView animateWithDuration:0.5 animations:^{
        flashView.alpha = 0;
        flashView.transform = CGAffineTransformMakeScale(2.0, 2.0);
    } completion:^(BOOL finished) {
        [flashView removeFromSuperview];
    }];
    
    if ([hitView isKindOfClass:[UIButton class]]) {
        [(UIButton*)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
        SALog(@"[Touch] Button touched successfully");
    } else if ([hitView isKindOfClass:[UIControl class]]) {
        [(UIControl*)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
        SALog(@"[Touch] Control touched successfully");
    } else {
        [hitView touchesBegan:[NSSet setWithObject:[UITouch new]] withEvent:nil];
        [hitView touchesEnded:[NSSet setWithObject:[UITouch new]] withEvent:nil];
        SALog(@"[Touch] View touched: %@", hitView);
    }
}

static void processPromptWithOpenAI(NSString *prompt, UIImage *screenshot) {
    CGFloat imgWidth = screenshot.size.width * screenshot.scale;
    CGFloat imgHeight = screenshot.size.height * screenshot.scale;

    static NSInteger retryCount = 0;
    static const NSInteger MAX_RETRIES = 3;
    static const NSTimeInterval RETRY_DELAY = 2.0;

    SALog(@"[OpenAI] Processing prompt: \"%@\" (Attempt: %ld)",
          prompt, (long)retryCount + 1);

    if (!screenshot) {
        SALog(@"[OpenAI] No screenshot provided");
        return;
    }

    NSData *imageData = UIImageJPEGRepresentation(screenshot, 0.8);
    NSString *base64Image = [imageData base64EncodedStringWithOptions:0];

    CGSize screenshotSize = screenshot.size;
    NSString *systemPrompt = [NSString stringWithFormat:
        @"You are an AI assistant that analyzes iOS screenshots to find UI elements. "
        "The screenshot resolution is %.0fx%.0f POINTS (not pixels). "
        "Device: iPad (7th generation), scale factor: 2.0. "
        "ALWAYS assume PORTRAIT orientation. "
        "The user will describe a UI element. "
        "You must respond ONLY with a JSON object containing the CENTER coordinates "
        "of that element in POINTS relative to this %.0fx%.0f points resolution. "
        "Format exactly: {\"x\": <number>, \"y\": <number>}. "
        "No text, no explanation, no markdown.",
        screenshotSize.width, screenshotSize.height,
        screenshotSize.width, screenshotSize.height
    ];

    NSArray *messages = @[
        @{@"role": @"system", @"content": systemPrompt},
        @{
            @"role": @"user",
            @"content": @[
                @{@"type": @"text", @"text": prompt},
                @{@"type": @"image_url",
                  @"image_url": @{@"url": [NSString stringWithFormat:@"data:image/jpeg;base64,%@", base64Image]}}
            ]
        }
    ];

    NSDictionary *payload = @{
        @"model": @"gpt-4o",
        @"messages": messages,
        @"max_tokens": @150,
        @"temperature": @0.1
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:OPENAI_API_URL]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", OPENAI_API_KEY] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:30.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (httpResponse.statusCode == 429 && retryCount < MAX_RETRIES) {
            retryCount++;
            SALog(@"[OpenAI] Rate limit hit, retrying in %.1f seconds (Attempt %ld/%ld)",
                  RETRY_DELAY, (long)retryCount, (long)MAX_RETRIES);

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(RETRY_DELAY * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                processPromptWithOpenAI(prompt, screenshot);
            });
            return;
        }

        retryCount = 0;

        if (error || httpResponse.statusCode != 200) {
            SALog(@"[OpenAI] Error: %@ (Status: %ld)",
                  error ? error.localizedDescription : @"API Error",
                  (long)httpResponse.statusCode);
            return;
        }

        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *choices = responseDict[@"choices"];
        if (choices && choices.count > 0) {
            NSString *content = choices[0][@"message"][@"content"];
            SALog(@"[OpenAI] AI response: %@", content);

            dispatch_async(dispatch_get_main_queue(), ^{
                parseCoordinatesAndTouch(content, screenshot.size);
            });
        }
    }];

    [task resume];
}

static void testOpenAITextOnly(NSString *prompt) {
    SALog(@"[TestOpenAI] Sending text-only prompt: %@", prompt);

    NSDictionary *payload = @{
        @"model": @"gpt-3.5-turbo",
        @"messages": @[@{@"role": @"user", @"content": prompt}],
        @"max_tokens": @50,
        @"temperature": @0.1
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:OPENAI_API_URL]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", OPENAI_API_KEY] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:30.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            SALog(@"[TestOpenAI] Network error: %@", error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            SALog(@"[TestOpenAI] API error: %ld", (long)httpResponse.statusCode);
            return;
        }

        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *choices = responseDict[@"choices"];
        if (choices && choices.count > 0) {
            NSString *content = choices[0][@"message"][@"content"];
            SALog(@"[TestOpenAI] AI response: %@", content);
        }
    }];

    [task resume];
}

static UIImage* drawDebugDot(UIImage *img, CGPoint point) {
    UIGraphicsBeginImageContextWithOptions(img.size, NO, img.scale);
    [img drawAtPoint:CGPointZero];

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(point.x - 10, point.y - 10, 20, 20));

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static void saveDebugImage(UIImage *image, NSString *name) {
    NSData *jpgData = UIImageJPEGRepresentation(image, 0.8);
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Caches/%@.jpg", name];
    [jpgData writeToFile:path atomically:YES];
    SALog(@"[Debug] Saved debug image: %@", path);
}

static void parseCoordinatesAndTouch(NSString *aiResponse, CGSize screenshotSize) {
    NSRange jsonStart = [aiResponse rangeOfString:@"{"];
    NSRange jsonEnd = [aiResponse rangeOfString:@"}" options:NSBackwardsSearch];

    if (jsonStart.location == NSNotFound || jsonEnd.location == NSNotFound) {
        SALog(@"[OpenAI] No valid JSON found in response: %@", aiResponse);
        return;
    }

    NSString *jsonString = [aiResponse substringWithRange:NSMakeRange(jsonStart.location, jsonEnd.location - jsonStart.location + 1)];
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    NSDictionary *coordinates = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&err];

    if (err || ![coordinates isKindOfClass:[NSDictionary class]]) {
        SALog(@"[OpenAI] JSON parse error: %@  raw: %@", err.localizedDescription, jsonString);
        return;
    }

    id xObj = coordinates[@"x"];
    id yObj = coordinates[@"y"];
    if (!xObj || !yObj) {
        SALog(@"[OpenAI] JSON missing x/y: %@", jsonString);
        return;
    }

    CGFloat aiX = [xObj floatValue];
    CGFloat aiY = [yObj floatValue];

    SALog(@"[OpenAI] Raw AI coords: (%.1f, %.1f)", aiX, aiY);
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    SALog(@"[OpenAI] Screen bounds: %.0fx%.0f", screenBounds.size.width, screenBounds.size.height);
    SALog(@"[OpenAI] Screenshot size: %.0fx%.0f", screenshotSize.width, screenshotSize.height);
    
    CGPoint mappedPoint;
    
    if (screenshotSize.width != screenBounds.size.width || screenshotSize.height != screenBounds.size.height) {
        CGFloat scaleX = screenBounds.size.width / screenshotSize.width;
        CGFloat scaleY = screenBounds.size.height / screenshotSize.height;
        
        mappedPoint = CGPointMake(aiX * scaleX, aiY * scaleY);
        SALog(@"[OpenAI] Scaled coordinates: (%.1f, %.1f) [scale factors: x:%.2f, y:%.2f]",
              mappedPoint.x, mappedPoint.y, scaleX, scaleY);
    } else {
        mappedPoint = CGPointMake(aiX, aiY);
        SALog(@"[OpenAI] Using direct coordinates: (%.1f, %.1f)", mappedPoint.x, mappedPoint.y);
    }
    
    CGFloat scale = [UIScreen mainScreen].scale;
    SALog(@"[OpenAI] Screen scale factor: %.1f", scale);
    
    mappedPoint = CGPointMake(mappedPoint.x * scale, mappedPoint.y * scale);
    SALog(@"[OpenAI] After scale adjustment: (%.1f, %.1f)", mappedPoint.x, mappedPoint.y);

    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    SALog(@"[OpenAI] Current orientation: %ld", (long)orientation);
    
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
        CGFloat statusBarHeight = 20.0;
        CGFloat homeIndicatorHeight = 20.0;
        
        if (mappedPoint.y < statusBarHeight + 10) {
            mappedPoint.y = statusBarHeight + 10;
        }
        
        if (mappedPoint.y > screenBounds.size.height * scale - homeIndicatorHeight - 10) {
            mappedPoint.y = screenBounds.size.height * scale - homeIndicatorHeight - 10;
        }
        
        SALog(@"[OpenAI] After portrait adjustment: (%.1f, %.1f)", mappedPoint.x, mappedPoint.y);
    }

    CGFloat margin = 20.0 * scale;
    CGFloat maxX = screenBounds.size.width * scale - margin;
    CGFloat maxY = screenBounds.size.height * scale - margin;
    
    if (mappedPoint.x < margin || mappedPoint.x > maxX ||
        mappedPoint.y < margin || mappedPoint.y > maxY) {
        
        SALog(@"[OpenAI] WARNING: Coordinates out of safe area: (%.1f, %.1f) - max: (%.1f, %.1f)",
              mappedPoint.x, mappedPoint.y, maxX, maxY);
        
        mappedPoint.x = MAX(margin, MIN(mappedPoint.x, maxX));
        mappedPoint.y = MAX(margin, MIN(mappedPoint.y, maxY));
        
        SALog(@"[OpenAI] Adjusted to safe area: (%.1f, %.1f)", mappedPoint.x, mappedPoint.y);
    }

    UIImage *screenshot = captureScreenshot();
    if (screenshot) {
        CGPoint debugPoint = CGPointMake(aiX, aiY);
        UIImage *debugImg = drawDebugDot(screenshot, debugPoint);
        saveDebugImage(debugImg, @"ai_debug_corrected");
    }

    SALog(@"[OpenAI] Final touch coordinates: (%.1f, %.1f) pixels", mappedPoint.x, mappedPoint.y);
    performFakeTouch(mappedPoint);
}

static void testCoordinateMapping() {
    UIImage *testScreenshot = captureScreenshot();
    if (testScreenshot) {
        SALog(@"[Debug] Test Screenshot: %.0fx%.0f points, scale: %.1f",
              testScreenshot.size.width, testScreenshot.size.height, testScreenshot.scale);
        SALog(@"[Debug] Screen bounds: %.0fx%.0f",
              [UIScreen mainScreen].bounds.size.width,
              [UIScreen mainScreen].bounds.size.height);
    }
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    SALog(@"[Hook] SpringBoard loaded");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[FloatingButtonManager shared] showFloatingButton];
    });
}
%end

%ctor {
    SALog(@"[Constructor] Button-based Voice Assistant loaded!");
    SALog(@"[Constructor] Features: Button recording, OpenAI Vision API, Touch simulation");
    
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [[FloatingButtonManager shared] showFloatingButton];
        });
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
           testCoordinateMapping();
        });
    }
}
