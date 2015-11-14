//
//  XMPhotoCollectionViewController.m
//  XMPhotos
//
//  Created by mifit on 15/11/14.
//  Copyright © 2015年 mifit. All rights reserved.
//

#import "XMPhotoCollectionViewController.h"
#import "XMPhotosCollectionViewCell.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

@implementation UICollectionView (Convenience)
- (NSArray *)aapl_indexPathsForElementsInRect:(CGRect)rect {
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}
@end

@interface XMPhotoCollectionViewController ()<PHPhotoLibraryChangeObserver>{
    ALAssetsLibrary *_assetsLibrary;
    
    PHAssetCollection *_assetCollection;
    PHFetchResult *_albums;
    PHCachingImageManager *_imageManager;
}
@property (nonatomic,strong) NSMutableArray *arrThumbnail;
@property (nonatomic,strong) NSMutableArray *arrOrg;
@property (nonatomic,copy) PhotoSelectedBlock block;
@property CGRect previousPreheatRect;
@end

@implementation XMPhotoCollectionViewController
static CGSize AssetGridThumbnailSize;
static NSString * const reuseIdentifier = @"XMPhotosCollectionViewCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    _arrThumbnail = [NSMutableArray array];
    _arrOrg = [NSMutableArray array];
    if (_numPerLine <= 0) {
        _numPerLine = 3;
    }
    if (_proportion <= 0) {
        _proportion = 1.0f;
    }
    
    [self imageFromAssert];
}

- (void)viewWillAppear:(BOOL)animated{
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        CGFloat scale = [UIScreen mainScreen].scale;
        CGSize cellSize = ((UICollectionViewFlowLayout *)self.collectionViewLayout).itemSize;
        AssetGridThumbnailSize = CGSizeMake(cellSize.width * scale, cellSize.height * scale);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        [self updateCachedAssets];
    }
}

- (void)dealloc {
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    }
    _arrOrg = nil;
    _arrThumbnail = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setSelectedBlock:(PhotoSelectedBlock)block{
    self.block = block;
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (void)imageFromAssert{
    if ([[UIDevice currentDevice].systemVersion floatValue] < 8.6) {
        _assetsLibrary = [[ALAssetsLibrary alloc] init];
        [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            if (group) {
                [group enumerateAssetsUsingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                    if (result) {
                        UIImage *image = [UIImage imageWithCGImage:[result aspectRatioThumbnail]];
                        NSString *url = [NSString stringWithFormat:@"%@", [[result defaultRepresentation] url]];
                        [self.arrThumbnail addObject:image];
                        [self.arrOrg addObject:url];
                        [self.collectionView reloadData];
                    }
                }];
            }
        } failureBlock:^(NSError *error) {
            NSLog(@"---Group not found!\n");
        }];
    }
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        PHFetchOptions *options = [[PHFetchOptions alloc] init];
        /// 按创建日期排序
        options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
        _albums = [PHAsset fetchAssetsWithOptions:options];
        NSLog(@"images count:%ld",(long)_albums.count);
        [[PHPhotoLibrary sharedPhotoLibrary]registerChangeObserver:self];
        _imageManager = [[PHCachingImageManager alloc] init];
        [_imageManager stopCachingImagesForAllAssets];
    }
}

- (void)updateCachedAssets {
    BOOL isViewVisible = [self isViewLoaded] && [[self view] window] != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0f, -0.5f * CGRectGetHeight(preheatRect));
    
    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0f) {
        
        // Compute the assets to start caching and to stop caching.
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        } addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self.collectionView aapl_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        [_imageManager startCachingImagesForAssets:assetsToStartCaching
                                        targetSize:AssetGridThumbnailSize
                                       contentMode:PHImageContentModeAspectFill
                                           options:nil];
        [_imageManager stopCachingImagesForAssets:assetsToStopCaching
                                       targetSize:AssetGridThumbnailSize
                                      contentMode:PHImageContentModeAspectFill
                                          options:nil];
        
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect removedHandler:(void (^)(CGRect removedRect))removedHandler addedHandler:(void (^)(CGRect addedRect))addedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths {
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        PHAsset *asset = _albums[indexPath.item];
        [assets addObject:asset];
    }
    return assets;
}

- (void)selectedImage:(NSInteger)index{
    ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
    NSURL *url = [NSURL URLWithString:[self.arrOrg objectAtIndex:index]];

    [assetLibrary assetForURL:url resultBlock:^(ALAsset *asset)  {
        if ([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypePhoto]) {
            if (self.block) {
                CGImageRef ref = [[asset defaultRepresentation] fullScreenImage];
                UIImage *image = [[UIImage alloc] initWithCGImage:ref];
                self.block(image,index);
            }
        }
    }failureBlock:^(NSError *error) {
        NSLog(@"error=%@",error);
    }];
}

- (void)PHSelectedInmage:(NSInteger)index{
    PHAsset *asset = _albums[index];
    [_imageManager requestImageForAsset:asset
                             targetSize:AssetGridThumbnailSize
                            contentMode:PHImageContentModeAspectFill
                                options:nil
                          resultHandler:^(UIImage *result, NSDictionary *info) {
                              NSString *str = info[@"PHImageFileSandboxExtensionTokenKey"];
                              if (str) {
                                  if (self.block) {
                                  self.block(result,index);
                                  }
                              }
                          }];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance{
    
}
#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        [self updateCachedAssets];
    }
}

/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

#pragma mark <UICollectionViewDataSource>

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        return _albums.count;
    }
    return self.arrThumbnail.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    XMPhotosCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"XMPhotosCollectionViewCell" forIndexPath:indexPath];
    if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
        NSInteger currentTag = cell.tag + 1;
        cell.tag = currentTag;
        PHAsset *asset = _albums[indexPath.item];
        [_imageManager requestImageForAsset:asset
                                 targetSize:AssetGridThumbnailSize
                                contentMode:PHImageContentModeAspectFill
                                    options:nil
                              resultHandler:^(UIImage *result, NSDictionary *info) {
                                  // Only update the thumbnail if the cell tag hasn't changed. Otherwise, the cell has been re-used.
                                  if (cell.tag == currentTag) {
                                      cell.imageView.image = result;
                                  }
                              }];
    }
    if ([[UIDevice currentDevice].systemVersion floatValue] < 8.6) {
        cell.imageView.image = [self.arrThumbnail objectAtIndex:indexPath.row];
    }
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    return cell;
}

#pragma mark <UICollectionViewDelegate>
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath{
    CGSize size = collectionView.frame.size;
    size.width = (size.width - self.numPerLine * 10 - 10) / self.numPerLine;
    size.height = size.width / self.proportion;
    return size;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath{
     if ([[UIDevice currentDevice].systemVersion floatValue] < 8.6) {
         [self selectedImage:indexPath.row];
     }
     if ([[UIDevice currentDevice].systemVersion floatValue] > 8.6) {
         [self PHSelectedInmage:indexPath.row];
     }
}
@end
