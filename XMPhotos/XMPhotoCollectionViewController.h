//
//  XMPhotoCollectionViewController.h
//  XMPhotos
//
//  Created by mifit on 15/11/14.
//  Copyright © 2015年 mifit. All rights reserved.
//

#import <UIKit/UIKit.h>
/// 相册cell点击响应block
typedef void (^PhotoSelectedBlock)(UIImage *image,NSInteger index);

@interface XMPhotoCollectionViewController : UICollectionViewController
@property (nonatomic,assign) NSInteger numPerLine;// 每行cell的个数，默认3个
@property (nonatomic,assign) CGFloat proportion;// cell的宽高比,默认1：1
- (void)setSelectedBlock:(PhotoSelectedBlock)block;
@end
