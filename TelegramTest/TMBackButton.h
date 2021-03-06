//
//  TMBackButton.h
//  Messenger for Telegram
//
//  Created by Dmitry Kondratyev on 3/8/14.
//  Copyright (c) 2014 keepcoder. All rights reserved.
//

#import "TMTextField.h"
#import "TMTextButton.h"
#import "TMViewController.h"
@interface TMBackButton : TMTextButton

typedef enum {
    TMBackButtonClose,
    TMBackButtonBack
} TMBackButtonType;

-(void)setTarget:(id)target selector:(SEL)selector;

@property (nonatomic,strong) TMViewController *controller;

- (id)initWithFrame:(NSRect)frame string:(NSString *)string;

@property (nonatomic, strong) NSImageView *imageView;

-(void)updateBackButton;

@end
