/*
 * StupidJailbreak.m
 *
 * Copyright (c) 2018 - NoMod-Programming (Edward P.)
 */

#import "StupidJailbreak.h"
#import "jailbreak.h"

@interface StupidJailbreak ()

@end

@implementation StupidJailbreak

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    // Here, all we're checking is if we have a bootstrap or not... Hopefully this will work?
    self.bootstrapSwitch.on = ![[NSFileManager defaultManager]fileExistsAtPath:@"/Applications/Cydia.app/"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)failedWithError:(NSString*)error{
    [self.statusLabel setTextColor:[UIColor redColor]];
    self.statusLabel.text = error;
}

- (IBAction)btnRunPressed:(id)sender {
    int err;

    self.progressBar.progress = 0.1; // Just in case; my first time using one, might as well
    self.progressBar.hidden = NO;
    self.statusLabel.hidden = NO;
    self.runButton.enabled = NO;
    [self.runButton setTitle: @"Running..." forState: UIControlStateDisabled];
    self.statusLabel.text = @"Starting...";
    [self.view setNeedsDisplay];
    if ((err = jailbreak(self.progressBar, self.statusLabel, [self.bootstrapSwitch isOn], [self.forceBootstrapSwitch isOn]))) {
        // Errored? WTF just log this and deal with this later
        NSLog(@"Error Code %d", err);
    } else {
        // Shouldn't we have resprung by now? Either way, let's log that the
        // jailbreak was a "success" just in case this doesn't do that immediately
        [self.runButton setTitle: @"Done?" forState: UIControlStateDisabled];
    }
}

- (IBAction)bootstrapSwitchChanged:(id)sender {
    if ([self.bootstrapSwitch isOn]) {
        [self.forceBootstrapSwitch setEnabled: YES];
    } else {
        self.forceBootstrapSwitch.enabled = NO;
        self.forceBootstrapSwitch.on = NO;
    }
}

@end
