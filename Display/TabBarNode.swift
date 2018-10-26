import Foundation
import UIKit
import AsyncDisplayKit

private let separatorHeight: CGFloat = 1.0 / UIScreen.main.scale
private func tabBarItemImage(_ image: UIImage?, title: String, backgroundColor: UIColor, tintColor: UIColor, horizontal: Bool) -> (UIImage, CGFloat) {
    let font = horizontal ? Font.regular(13.0) : Font.medium(10.0)
    let titleSize = (title as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [NSAttributedStringKey.font: font], context: nil).size
    
    let imageSize: CGSize
    if let image = image {
        if horizontal {
            let factor: CGFloat = 0.8
            imageSize = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
        } else {
            imageSize = image.size
        }
    } else {
        imageSize = CGSize()
    }
    
    let horizontalSpacing: CGFloat = 4.0
    
    let size: CGSize
    let contentWidth: CGFloat
    if horizontal {
        size = CGSize(width: ceil(titleSize.width) + horizontalSpacing + imageSize.width, height: 34.0)
        contentWidth = size.width
    } else {
        size = CGSize(width: max(ceil(titleSize.width), imageSize.width), height: 45.0)
        contentWidth = imageSize.width
    }
    
    UIGraphicsBeginImageContextWithOptions(size, true, 0.0)
    if let context = UIGraphicsGetCurrentContext() {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
        
        if let image = image {
            if horizontal {
                let imageRect = CGRect(origin: CGPoint(x: 0.0, y: floor((size.height - imageSize.height) / 2.0)), size: imageSize)
                context.saveGState()
                context.translateBy(x: imageRect.midX, y: imageRect.midY)
                context.scaleBy(x: 1.0, y: -1.0)
                context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
                context.clip(to: imageRect, mask: image.cgImage!)
                context.setFillColor(tintColor.cgColor)
                context.fill(imageRect)
                context.restoreGState()
            } else {
                let imageRect = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - imageSize.width) / 2.0), y: 1.0), size: imageSize)
                context.saveGState()
                context.translateBy(x: imageRect.midX, y: imageRect.midY)
                context.scaleBy(x: 1.0, y: -1.0)
                context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
                context.clip(to: imageRect, mask: image.cgImage!)
                context.setFillColor(tintColor.cgColor)
                context.fill(imageRect)
                context.restoreGState()
            }
        }
    }
    
    if horizontal {
        (title as NSString).draw(at: CGPoint(x: imageSize.width + horizontalSpacing, y: floor((size.height - titleSize.height) / 2.0) - 2.0), withAttributes: [NSAttributedStringKey.font: font, NSAttributedStringKey.foregroundColor: tintColor])
    } else {
        (title as NSString).draw(at: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: size.height - titleSize.height - 2.0), withAttributes: [NSAttributedStringKey.font: font, NSAttributedStringKey.foregroundColor: tintColor])
    }
    
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return (image!, contentWidth)
}

private let badgeFont = Font.regular(13.0)

private final class TabBarItemNode: ASImageNode {
    var contentWidth: CGFloat?
}

private final class TabBarNodeContainer {
    let item: UITabBarItem
    let updateBadgeListenerIndex: Int
    let updateTitleListenerIndex: Int
    let updateImageListenerIndex: Int
    let updateSelectedImageListenerIndex: Int
    
    let imageNode: TabBarItemNode
    let badgeContainerNode: ASDisplayNode
    let badgeBackgroundNode: ASImageNode
    let badgeTextNode: ASTextNode
    
    var badgeValue: String?
    var appliedBadgeValue: String?
    
    var titleValue: String?
    var appliedTitleValue: String?
    
    var imageValue: UIImage?
    var appliedImageValue: UIImage?
    
    var selectedImageValue: UIImage?
    var appliedSelectedImageValue: UIImage?
    
    init(item: UITabBarItem, imageNode: TabBarItemNode, updateBadge: @escaping (String) -> Void, updateTitle: @escaping (String, Bool) -> Void, updateImage: @escaping (UIImage?) -> Void, updateSelectedImage: @escaping (UIImage?) -> Void) {
        self.item = item
        
        self.imageNode = imageNode
        
        self.badgeContainerNode = ASDisplayNode()
        self.badgeContainerNode.isLayerBacked = true
        
        self.badgeBackgroundNode = ASImageNode()
        self.badgeBackgroundNode.isLayerBacked = true
        self.badgeBackgroundNode.displayWithoutProcessing = true
        self.badgeBackgroundNode.displaysAsynchronously = false
        
        self.badgeTextNode = ASTextNode()
        self.badgeTextNode.maximumNumberOfLines = 1
        self.badgeTextNode.isLayerBacked = true
        self.badgeTextNode.displaysAsynchronously = false
        
        self.badgeContainerNode.addSubnode(self.badgeBackgroundNode)
        self.badgeContainerNode.addSubnode(self.badgeTextNode)
        
        self.badgeValue = item.badgeValue ?? ""
        self.updateBadgeListenerIndex = UITabBarItem_addSetBadgeListener(item, { value in
            updateBadge(value ?? "")
        })
        
        self.titleValue = item.title
        self.updateTitleListenerIndex = item.addSetTitleListener { value, animated in
            updateTitle(value ?? "", animated)
        }
        
        self.imageValue = item.image
        self.updateImageListenerIndex = item.addSetImageListener { value in
            updateImage(value)
        }
        
        self.selectedImageValue = item.selectedImage
        self.updateSelectedImageListenerIndex = item.addSetSelectedImageListener { value in
            updateSelectedImage(value)
        }
    }
    
    deinit {
        item.removeSetBadgeListener(self.updateBadgeListenerIndex)
        item.removeSetTitleListener(self.updateTitleListenerIndex)
        item.removeSetImageListener(self.updateImageListenerIndex)
        item.removeSetSelectedImageListener(self.updateSelectedImageListenerIndex)
    }
}

class TabBarNode: ASDisplayNode {
    var tabBarItems: [UITabBarItem] = [] {
        didSet {
            self.reloadTabBarItems()
        }
    }
    
    var selectedIndex: Int? {
        didSet {
            if self.selectedIndex != oldValue {
                if let oldValue = oldValue {
                    self.updateNodeImage(oldValue, layout: true)
                }
                
                if let selectedIndex = self.selectedIndex {
                    self.updateNodeImage(selectedIndex, layout: true)
                }
            }
        }
    }
    
    private let itemSelected: (Int, Bool) -> Void
    
    private var theme: TabBarControllerTheme
    private var validLayout: (CGSize, CGFloat, CGFloat, CGFloat)?
    private var horizontal: Bool = false
    
    private var badgeImage: UIImage
    
    let separatorNode: ASDisplayNode
    private var tabBarNodeContainers: [TabBarNodeContainer] = []
    
    init(theme: TabBarControllerTheme, itemSelected: @escaping (Int, Bool) -> Void) {
        self.itemSelected = itemSelected
        self.theme = theme
        
        self.separatorNode = ASDisplayNode()
        self.separatorNode.backgroundColor = theme.tabBarSeparatorColor
        self.separatorNode.isOpaque = true
        self.separatorNode.isLayerBacked = true
        
        self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.tabBarBadgeBackgroundColor, strokeColor: theme.tabBarBadgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
        
        super.init()
        
        self.isOpaque = true
        self.backgroundColor = theme.tabBarBackgroundColor
        
        self.addSubnode(self.separatorNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(TabBarTapRecognizer(tap: { [weak self] point in
            self?.tapped(at: point, longTap: false)
        }, longTap: { [weak self] point in
            self?.tapped(at: point, longTap: true)
        }))
    }
    
    func updateTheme(_ theme: TabBarControllerTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            self.separatorNode.backgroundColor = theme.tabBarSeparatorColor
            self.backgroundColor = theme.tabBarBackgroundColor
            
            self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.tabBarBadgeBackgroundColor, strokeColor: theme.tabBarBadgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
            for container in self.tabBarNodeContainers {
                if let attributedText = container.badgeTextNode.attributedText, !attributedText.string.isEmpty {
                    container.badgeTextNode.attributedText = NSAttributedString(string: attributedText.string, font: badgeFont, textColor: self.theme.tabBarBadgeTextColor)
                }
            }
            
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
                
                self.tabBarNodeContainers[i].badgeBackgroundNode.image = self.badgeImage
            }
        }
    }
    
    private func reloadTabBarItems() {
        for node in self.tabBarNodeContainers {
            node.imageNode.removeFromSupernode()
            node.badgeContainerNode.removeFromSupernode()
        }
        
        var tabBarNodeContainers: [TabBarNodeContainer] = []
        for i in 0 ..< self.tabBarItems.count {
            let item = self.tabBarItems[i]
            let node = TabBarItemNode()
            node.displaysAsynchronously = false
            node.displayWithoutProcessing = true
            node.isLayerBacked = true
            let container = TabBarNodeContainer(item: item, imageNode: node, updateBadge: { [weak self] value in
                self?.updateNodeBadge(i, value: value)
            }, updateTitle: { [weak self] _, _ in
                self?.updateNodeImage(i, layout: true)
            }, updateImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, updateSelectedImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            })
            if let selectedIndex = self.selectedIndex, selectedIndex == i {
                let (image, contentWidth) = tabBarItemImage(item.selectedImage, title: item.title ?? "", backgroundColor: self.theme.tabBarBackgroundColor, tintColor: self.theme.tabBarSelectedTextColor, horizontal: self.horizontal)
                node.image = image
                node.contentWidth = contentWidth
            } else {
                let (image, contentWidth) = tabBarItemImage(item.image, title: item.title ?? "", backgroundColor: self.theme.tabBarBackgroundColor, tintColor: self.theme.tabBarTextColor, horizontal: self.horizontal)
                node.image = image
                node.contentWidth = contentWidth
            }
            container.badgeBackgroundNode.image = self.badgeImage
            tabBarNodeContainers.append(container)
            self.addSubnode(node)
        }
        
        for container in tabBarNodeContainers {
            self.addSubnode(container.badgeContainerNode)
        }
        
        self.tabBarNodeContainers = tabBarNodeContainers
        
        self.setNeedsLayout()
    }
    
    private func updateNodeImage(_ index: Int, layout: Bool) {
        if index < self.tabBarNodeContainers.count && index < self.tabBarItems.count {
            let node = self.tabBarNodeContainers[index].imageNode
            let item = self.tabBarItems[index]
            
            let previousImage = node.image
            if let selectedIndex = self.selectedIndex, selectedIndex == index {
                let (image, contentWidth) = tabBarItemImage(item.selectedImage, title: item.title ?? "", backgroundColor: self.theme.tabBarBackgroundColor, tintColor: self.theme.tabBarSelectedTextColor, horizontal: self.horizontal)
                node.image = image
                node.contentWidth = contentWidth
            } else {
                let (image, contentWidth) = tabBarItemImage(item.image, title: item.title ?? "", backgroundColor: self.theme.tabBarBackgroundColor, tintColor: self.theme.tabBarTextColor, horizontal: self.horizontal)
                node.image = image
                node.contentWidth = contentWidth
            }
            if previousImage?.size != node.image?.size {
                if let validLayout = self.validLayout, layout {
                    self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, bottomInset: validLayout.3, transition: .immediate)
                }
            }
        }
    }
    
    private func updateNodeBadge(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].badgeValue = value
        if self.tabBarNodeContainers[index].badgeValue != self.tabBarNodeContainers[index].appliedBadgeValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, bottomInset: validLayout.3, transition: .immediate)
            }
        }
    }
    
    private func updateNodeTitle(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].titleValue = value
        if self.tabBarNodeContainers[index].titleValue != self.tabBarNodeContainers[index].appliedTitleValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, bottomInset: validLayout.3, transition: .immediate)
            }
        }
    }
    
    func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, leftInset, rightInset, bottomInset)
        
        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -separatorHeight), size: CGSize(width: size.width, height: separatorHeight)))
        
        let horizontal = !leftInset.isZero
        if self.horizontal != horizontal {
            self.horizontal = horizontal
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
            }
        }
        
        if self.tabBarNodeContainers.count != 0 {
            let distanceBetweenNodes = size.width / CGFloat(self.tabBarNodeContainers.count)
            
            let internalWidth = distanceBetweenNodes * CGFloat(self.tabBarNodeContainers.count - 1)
            let leftNodeOriginX = (size.width - internalWidth) / 2.0
            
            for i in 0 ..< self.tabBarNodeContainers.count {
                let container = self.tabBarNodeContainers[i]
                let node = container.imageNode
                let nodeSize = node.image?.size ?? CGSize()
                
                let originX = floor(leftNodeOriginX + CGFloat(i) * distanceBetweenNodes - nodeSize.width / 2.0)
                transition.updateFrame(node: node, frame: CGRect(origin: CGPoint(x: originX, y: 4.0), size: nodeSize))
                
                if container.badgeValue != container.appliedBadgeValue {
                    container.appliedBadgeValue = container.badgeValue
                    if let badgeValue = container.badgeValue, !badgeValue.isEmpty {
                        container.badgeTextNode.attributedText = NSAttributedString(string: badgeValue, font: badgeFont, textColor: self.theme.tabBarBadgeTextColor)
                        container.badgeContainerNode.isHidden = false
                    } else {
                        container.badgeContainerNode.isHidden = true
                    }
                }
                
                if !container.badgeContainerNode.isHidden {
                    let badgeSize = container.badgeTextNode.measure(CGSize(width: 200.0, height: 100.0))
                    let backgroundSize = CGSize(width: max(18.0, badgeSize.width + 10.0 + 1.0), height: 18.0)
                    let backgroundFrame: CGRect
                    if horizontal {
                        backgroundFrame = CGRect(origin: CGPoint(x: originX, y: 2.0), size: backgroundSize)
                    } else {
                        let contentWidth = node.contentWidth ?? node.frame.width
                        backgroundFrame = CGRect(origin: CGPoint(x: floor(originX + node.frame.width / 2.0) - 1.0 + contentWidth - backgroundSize.width - 1.0, y: 2.0), size: backgroundSize)
                    }
                    transition.updateFrame(node: container.badgeContainerNode, frame: backgroundFrame)
                    container.badgeBackgroundNode.frame = CGRect(origin: CGPoint(), size: backgroundFrame.size)
                    let scaleFactor: CGFloat = horizontal ? 0.8 : 1.0
                    container.badgeContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                    
                    container.badgeTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundFrame.size.width - badgeSize.width) / 2.0), y: 1.0), size: badgeSize)
                }
            }
        }
    }
    
    private func tapped(at location: CGPoint, longTap: Bool) {
        if let bottomInset = self.validLayout?.3 {
            if location.y > self.bounds.size.height - bottomInset {
                return
            }
            var closestNode: (Int, CGFloat)?
            
            for i in 0 ..< self.tabBarNodeContainers.count {
                let node = self.tabBarNodeContainers[i].imageNode
                let distance = abs(location.x - node.position.x)
                if let previousClosestNode = closestNode {
                    if previousClosestNode.1 > distance {
                        closestNode = (i, distance)
                    }
                } else {
                    closestNode = (i, distance)
                }
            }
            
            if let closestNode = closestNode {
                self.itemSelected(closestNode.0, longTap)
            }
        }
    }
}
