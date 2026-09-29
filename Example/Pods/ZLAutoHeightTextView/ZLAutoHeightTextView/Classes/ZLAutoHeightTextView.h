//
//  ZLAutoHeightTextView.h
//  ZLAutoHeightTextView
//
//  Created by admin on 2026/3/30.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
IB_DESIGNABLE
@interface ZLAutoHeightTextView : UITextView
@property (nonatomic, assign) IBInspectable CGFloat maxHeight;
@property (nonatomic, assign) IBInspectable CGFloat minHeight;
@property (nonatomic, copy) void(^heightDidChangeBlock)(CGFloat newHeight);
@property (nonatomic, copy) IBInspectable NSString *placeholder;
@property (nonatomic, strong) IBInspectable UIColor *placeholderColor;
@end
NS_ASSUME_NONNULL_END
