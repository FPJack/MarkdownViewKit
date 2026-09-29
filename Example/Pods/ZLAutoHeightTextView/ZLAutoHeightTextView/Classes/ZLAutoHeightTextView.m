//
//  ZLAutoHeightTextView.m
//  ZLAutoHeightTextView
//
//  Created by admin on 2026/3/30.
//

#import "ZLAutoHeightTextView.h"

@implementation ZLAutoHeightTextView {
    UILabel *_placeholderLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupDefaults];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupDefaults];
    }
    return self;
}

- (void)setupDefaults {
    _maxHeight = 0;
    _minHeight = 0;
    _placeholderColor = [UIColor colorWithRed:0.78 green:0.78 blue:0.80 alpha:1.0];
    self.scrollEnabled = NO;
    self.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    
    [self setupPlaceholderLabel];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textDidChange:)
                                                 name:UITextViewTextDidChangeNotification
                                               object:self];
}

- (void)setupPlaceholderLabel {
    _placeholderLabel = [[UILabel alloc] init];
    _placeholderLabel.numberOfLines = 0;
    _placeholderLabel.textColor = _placeholderColor;
    _placeholderLabel.backgroundColor = UIColor.clearColor;
    _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_placeholderLabel];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = [placeholder copy];
    _placeholderLabel.text = placeholder;
    [self updatePlaceholderVisibility];
}

- (void)setPlaceholderColor:(UIColor *)placeholderColor {
    _placeholderColor = placeholderColor;
    _placeholderLabel.textColor = placeholderColor;
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    _placeholderLabel.font = font;
    [self updateHeight];
}

- (void)setTextContainerInset:(UIEdgeInsets)textContainerInset {
    [super setTextContainerInset:textContainerInset];
    [self setNeedsLayout];
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self updatePlaceholderVisibility];
    [self updateHeight];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    [super setAttributedText:attributedText];
    [self updatePlaceholderVisibility];
    [self updateHeight];
}

- (void)textDidChange:(NSNotification *)notification {
    [self updatePlaceholderVisibility];
    [self updateHeight];
}

- (void)updatePlaceholderVisibility {
    _placeholderLabel.hidden = (self.text.length > 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 更新 placeholder 位置
    CGFloat lineFragmentPadding = self.textContainer.lineFragmentPadding;
    UIEdgeInsets insets = self.textContainerInset;
    
    CGFloat x = insets.left + lineFragmentPadding;
    CGFloat y = insets.top;
    CGFloat width = self.bounds.size.width - x - insets.right - lineFragmentPadding;
    
    CGSize size = [_placeholderLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    _placeholderLabel.frame = CGRectMake(x, y, width, size.height);
    
    [self updateHeight];
}

- (void)updateHeight {
    CGFloat contentHeight = [self calculateContentHeight];
    
    if (self.minHeight > 0 && contentHeight < self.minHeight) {
        contentHeight = self.minHeight;
    }
    
    BOOL shouldScroll = NO;
    if (self.maxHeight > 0 && contentHeight > self.maxHeight) {
        contentHeight = self.maxHeight;
        shouldScroll = YES;
    }
    
    self.scrollEnabled = shouldScroll;
    
    CGRect frame = self.frame;
    if (frame.size.height != contentHeight) {
        frame.size.height = contentHeight;
        self.frame = frame;
        [self invalidateIntrinsicContentSize];
        
        if (self.heightDidChangeBlock) {
            self.heightDidChangeBlock(contentHeight);
        }
    }
}

- (CGFloat)calculateContentHeight {
    CGFloat fixedWidth = self.frame.size.width;
    if (fixedWidth <= 0) {
        fixedWidth = UIScreen.mainScreen.bounds.size.width - 32;
    }
    
    CGSize sizeThatFits = [self sizeThatFits:CGSizeMake(fixedWidth, CGFLOAT_MAX)];
    return ceilf(sizeThatFits.height);
}

- (CGSize)intrinsicContentSize {
    CGFloat contentHeight = [self calculateContentHeight];
    
    if (self.minHeight > 0 && contentHeight < self.minHeight) {
        contentHeight = self.minHeight;
    }
    if (self.maxHeight > 0 && contentHeight > self.maxHeight) {
        contentHeight = self.maxHeight;
    }
    
    return CGSizeMake(UIViewNoIntrinsicMetric, contentHeight);
}

@end

