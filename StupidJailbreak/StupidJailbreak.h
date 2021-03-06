/*
 * GeneratorSetterVC.h - UI stuff
 *
 * Copyright (c) 2017 Siguza & tihmstar
 */

#import <UIKit/UIKit.h>

@interface StupidJailbreak : UIViewController
@property (weak, nonatomic) IBOutlet UIButton *runButton;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *progressBar;
@property (weak, nonatomic) IBOutlet UISwitch *bootstrapSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *forceBootstrapSwitch;
- (IBAction)btnRunPressed:(id)sender;

@end
