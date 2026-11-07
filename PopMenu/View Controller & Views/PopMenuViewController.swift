//
//  PopMenuViewController.swift
//  PopMenu
//
//  Created by Cali Castle on 4/12/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import UIKit

/// Delegate for handling PopMenu selection.
@objc public protocol PopMenuViewControllerDelegate: class {
    /// Called when an action is selected.
    @objc optional func popMenuDidSelectItem(_ popMenuViewController: PopMenuViewController, at index: Int)
}

final public class PopMenuViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Delegate instance for handling callbacks.
    public weak var delegate: PopMenuViewControllerDelegate?
    
    /// Appearance configuration.
    public var appearance = PopMenuAppearance()
    
    /// Background overlay that covers the whole screen.
    public let backgroundView = UIView()
    
    /// The blur overlay view for translucent illusion.
    private lazy var blurOverlayView: UIVisualEffectView = {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = appearance.popMenuCornerRadius
        blurView.layer.masksToBounds = true
        blurView.isUserInteractionEnabled = false
        
        return blurView
    }()
    
    /// Main root view that has shadows.
    public let containerView = UIView()
    
    /// Main content view.
    public let contentView = PopMenuGradientView()
    
    /// The view contains all the actions.
    public let actionsView = UIStackView()
    
    /// The source View to be displayed from.
    private(set) weak var sourceView: AnyObject?
    /// Optional tap/click location in sourceView coordinates; nil uses its bounds.
    private(set) var sourcePoint: CGPoint?
    
    /// The source frame in this presentation view's local coordinates.
    private(set) var absoluteSourceFrame: CGRect?
    private var lastLayoutBounds: CGRect?
    private var lastLayoutInsets: UIEdgeInsets?
    private var lastLayoutSourceFrame: CGRect?
    private var actionsScrollView: UIScrollView?
    
    /// The calculated content frame.
    public lazy var contentFrame: CGRect = {
        return calculateContentFittingFrame()
    }()
    
    // MARK: - Configurations
    
    /// Determines whether to dismiss menu after an action is selected.
    public var shouldDismissOnSelection: Bool = true
    
    /// Determines whether the pan gesture is enabled on the actions.
    public var shouldEnablePanGesture: Bool = true
    
    /// Determines whether enable haptics for iPhone 7 and up.
    public var shouldEnableHaptics: Bool = true
    
    /// Handler for when the menu is dismissed.
    public var didDismiss: ((Bool) -> Void)?
    
    // MARK: - Constraints
    
    private(set) var contentLeftConstraint: NSLayoutConstraint!
    private(set) var contentTopConstraint: NSLayoutConstraint!
    private(set) var contentWidthConstraint: NSLayoutConstraint!
    private(set) var contentHeightConstraint: NSLayoutConstraint!
    
    /// The UIView instance of source view.
    fileprivate lazy var sourceViewAsUIView: UIView? = {
        guard let sourceView = sourceView else { return nil }
        
        // Check if UIBarButtonItem
        if let sourceBarButtonItem = sourceView as? UIBarButtonItem {
            if let buttonView = sourceBarButtonItem.value(forKey: "view") as? UIView {
                return buttonView
            }
        }
        
        if let sourceView = sourceView as? UIView {
            return sourceView
        }
        
        return nil
    }()
    
    /// Tap gesture to dismiss for background view.
    fileprivate lazy var tapGestureForDismissal: UITapGestureRecognizer = {
        let tapper = UITapGestureRecognizer(target: self, action: #selector(backgroundViewDidTap(_:)))
        tapper.cancelsTouchesInView = false
        tapper.delaysTouchesEnded = false
        
        return tapper
    }()
    
    /// Pan gesture to highligh actions.
    fileprivate lazy var panGestureForMenu: UIPanGestureRecognizer = {
        let panner = UIPanGestureRecognizer(target: self, action: #selector(menuDidPan(_:)))
        panner.maximumNumberOfTouches = 1
        
        return panner
    }()
    
    /// Actions of menu.
    public private(set) var actions: [PopMenuAction] = []
    
    /// Max content width allowed for the content to stretch to.
    fileprivate var contentSafeAreaInsets: UIEdgeInsets {
        if #available(iOS 11.0, *) { return view.safeAreaInsets }
        return .zero
    }

    fileprivate var availableContentBounds: CGRect {
        let safeBounds = view.bounds.inset(by: contentSafeAreaInsets)
        let horizontalPadding = min(8, max(0, safeBounds.width / 2))
        let verticalPadding = min(8, max(0, safeBounds.height / 2))
        return safeBounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }

    fileprivate var maxContentWidth: CGFloat {
        return max(0, availableContentBounds.width)
    }
    
    // MARK: - View Life Cycle
    
    /// PopMenuViewController constructor
    ///
    /// - Parameters:
    ///   - sourceView: the source view for triggering the menu
    ///   - sourcePoint: optional tap/click point in sourceView coordinates; nil uses its bounds
    ///   - actions: all the menu actions
    ///   - appearance: appearance configuration
    public convenience init(sourceView: AnyObject? = nil, sourcePoint: CGPoint? = nil, actions: [PopMenuAction], appearance: PopMenuAppearance? = nil) {
        self.init(nibName: nil, bundle: nil)
        
        self.sourceView = sourceView
        self.sourcePoint = sourcePoint
        self.actions = actions

        // Assign appearance or use the default one.
        if let appearance = appearance {
            self.appearance = appearance
        }

        transitioningDelegate = self
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }
    
    /// Load view entry point.
    public override func loadView() {
        super.loadView()

        view.backgroundColor = .clear
        
        configureBackgroundView()
        configureContentView()
        configureActionsView()
    }
    
    /// Resolve the anchor only after attachment to the presentation container.
    fileprivate func setAbsoluteSourceFrame() {
        if let sourceView = sourceViewAsUIView {
            var ancestor: UIView? = sourceView
            while let current = ancestor {
                if view.isDescendant(of: current) {
                    let sourceRect = sourcePoint.map { CGRect(origin: $0, size: .zero) } ?? sourceView.bounds
                    absoluteSourceFrame = sourceView.convert(sourceRect, to: view)
                    return
                }
                ancestor = current.superview
            }
        }
        // If a previously resolved source scrolls away or is detached during
        // dismissal, retain its last local anchor instead of jumping to centre.
        // A source that has never shared this hierarchy remains unanchored.
    }

    /// Called by the animator after installing the final presentation frame.
    func prepareForPresentation() {
        updateContentLayout()
        view.layoutIfNeeded()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentLayout()
    }

    private func updateContentLayout() {
        setAbsoluteSourceFrame()
        guard lastLayoutBounds != view.bounds || lastLayoutInsets != contentSafeAreaInsets ||
                lastLayoutSourceFrame != absoluteSourceFrame else { return }
        lastLayoutBounds = view.bounds
        lastLayoutInsets = contentSafeAreaInsets
        lastLayoutSourceFrame = absoluteSourceFrame
        contentFrame = calculateContentFittingFrame()
        contentLeftConstraint.constant = contentFrame.minX
        contentTopConstraint.constant = contentFrame.minY
        contentWidthConstraint.constant = contentFrame.width
        contentHeightConstraint.constant = contentFrame.height
        let needsScrolling = CGFloat(actions.count) * appearance.popMenuActionHeight > contentFrame.height
        actionsScrollView?.isScrollEnabled = needsScrolling
        panGestureForMenu.isEnabled = !needsScrolling && actions.count < appearance.popMenuActionCountForScrollable
    }
    
    /// Add a new action to the menu.
    ///
    /// - Parameter action: Action to be added
    public func addAction(_ action: PopMenuAction) {
        actions.append(action)
    }
    
    // MARK: - Status Bar Appearance
    
    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    /// Set status bar style.
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        // If style defined, return
        if let statusBarStyle = appearance.popMenuStatusBarStyle {
            return statusBarStyle
        }
        
        // Contrast of blur style
        let backgroundStyle = appearance.popMenuBackgroundStyle
        if let blurStyle = backgroundStyle.blurStyle {
            switch blurStyle {
            case .dark:
                return .lightContent
            default:
                return .default
            }
        }
        
        // Contrast of dimmed color
        if let dimColor = backgroundStyle.dimColor {
            return dimColor.blackOrWhiteContrastingColor() == .white ? .lightContent : .default
        }
        
        return .lightContent
    }
    
    /// Handle when device orientation changed or container size changed.
    ///
    /// - Parameters:
    ///   - size: Changed size
    ///   - coordinator: Coordinator that manages the container
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }
    
}

// MARK: - View Configurations

extension PopMenuViewController {
    
    /// Setup the background view at the bottom.
    fileprivate func configureBackgroundView() {
        backgroundView.backgroundColor = .clear
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addGestureRecognizer(tapGestureForDismissal)
        backgroundView.isUserInteractionEnabled = true
        
        let backgroundStyle = appearance.popMenuBackgroundStyle
        
        // Blurred background
        if let isBlurred = backgroundStyle.isBlurred,
            isBlurred,
            let blurStyle = backgroundStyle.blurStyle {
            
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            blurView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(blurView)
            NSLayoutConstraint.activate([
                blurView.leftAnchor.constraint(equalTo: backgroundView.leftAnchor),
                blurView.rightAnchor.constraint(equalTo: backgroundView.rightAnchor),
                blurView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                blurView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
            ])
        }
        
        // Dimmed background
        if let isDimmed = backgroundStyle.isDimmed,
            isDimmed,
            let color = backgroundStyle.dimColor,
            let opacity = backgroundStyle.dimOpacity {
            
            backgroundView.backgroundColor = color.withAlphaComponent(opacity)
        }
        
        view.insertSubview(backgroundView, at: 0)
        NSLayoutConstraint.activate([
            backgroundView.leftAnchor.constraint(equalTo: view.leftAnchor),
            backgroundView.rightAnchor.constraint(equalTo: view.rightAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    /// Setup the content view.
    fileprivate func configureContentView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addShadow(offset: .init(width: 0, height: 1), opacity: 0.5, radius: 20)
        containerView.layer.cornerRadius = appearance.popMenuCornerRadius
        containerView.backgroundColor = .clear
        
        view.addSubview(containerView)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.cornerRadius = appearance.popMenuCornerRadius
        contentView.layer.masksToBounds = true
        contentView.clipsToBounds = true
        
        let colors = appearance.popMenuColor.backgroundColor.colors
        if colors.count > 0 {
            if colors.count == 1 {
                // Configure solid fill background.
                contentView.backgroundColor = colors.first?.withAlphaComponent(0.9)
                contentView.startColor = .clear
                contentView.endColor = .clear
            } else {
                // Configure gradient color.
                contentView.diagonalMode = true
                contentView.startColor = colors.first!
                contentView.endColor = colors.last!
                contentView.gradientLayer.opacity = 0.8
            }
        }

        containerView.addSubview(blurOverlayView)
        containerView.addSubview(contentView)
        
        setupContentConstraints()
    }
    
    /// Activate necessary constraints.
    fileprivate func setupContentConstraints() {
        contentLeftConstraint = containerView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: contentFrame.origin.x)
        contentTopConstraint = containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: contentFrame.origin.y)
        contentWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: contentFrame.size.width)
        contentHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: contentFrame.size.height)
        
        // Activate container view constraints
        NSLayoutConstraint.activate([
            contentLeftConstraint,
            contentTopConstraint,
            contentWidthConstraint,
            contentHeightConstraint
        ])
        // Activate content view constraints
        NSLayoutConstraint.activate([
            contentView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        // Activate blur overlay constraints
        NSLayoutConstraint.activate([
            blurOverlayView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            blurOverlayView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            blurOverlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurOverlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    /// Determine the fitting frame for content.
    ///
    /// - Returns: The fitting frame
    fileprivate func calculateContentFittingFrame() -> CGRect {
        var height: CGFloat
        
        if actions.count >= appearance.popMenuActionCountForScrollable {
            // Make scroll view
            height = CGFloat(appearance.popMenuActionCountForScrollable) * appearance.popMenuActionHeight
            height -= 20
        } else {
            height = CGFloat(actions.count) * appearance.popMenuActionHeight
        }
        
        let size = CGSize(width: calculateContentWidth(), height: min(height, max(0, availableContentBounds.height)))
        let origin = calculateContentOrigin(with: size)
        
        return CGRect(origin: origin, size: size)
    }
    
    /// Determine where the menu should display.
    ///
    /// - Returns: The source origin point
    fileprivate func calculateContentOrigin(with size: CGSize) -> CGPoint {
        let bounds = availableContentBounds
        let desiredOrigin: CGPoint
        if let sourceFrame = absoluteSourceFrame {
            if sourcePoint != nil {
                desiredOrigin = CGPoint(x: sourceFrame.minX + 8, y: sourceFrame.minY + 8)
            } else {
                desiredOrigin = CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.minY)
            }
        } else {
            desiredOrigin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        }
        return CGPoint(
            x: min(max(desiredOrigin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(desiredOrigin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }

    /// Determine the content width by the longest title possible.
    ///
    /// - Returns: The fitting width for content
    fileprivate func calculateContentWidth() -> CGFloat {
        var contentFitWidth: CGFloat = 0
        contentFitWidth += PopMenuDefaultAction.textLeftPadding * 2
        
        // Calculate the widest width from action titles to determine the width
        if let action = actions.max(by: {
            guard let title1 = $0.title, let title2 = $1.title else { return false }
            return title1.count < title2.count
        }) {
            let sizingLabel = UILabel()
            sizingLabel.text = action.title
            
            let desiredWidth = sizingLabel.sizeThatFits(view.bounds.size).width
            contentFitWidth += desiredWidth
            
            contentFitWidth += action.iconWidthHeight
        }
        
        return min(contentFitWidth,maxContentWidth)
    }
    
    /// Setup actions view.
    fileprivate func configureActionsView() {
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        actionsView.axis = .vertical
        actionsView.alignment = .fill
        actionsView.distribution = .fillEqually

        // Configure each action
        actions.forEach { action in
            action.font = appearance.popMenuFont
            action.tintColor = action.color ?? appearance.popMenuColor.actionColor.color
            action.cornerRadius = appearance.popMenuCornerRadius / 2
            action.renderActionView()
            
            // Give separator to each action but the last
            if !action.isEqual(actions.last) {
                addSeparator(to: action.view)
            }
            
            let tapper = UITapGestureRecognizer(target: self, action: #selector(menuDidTap(_:)))
            tapper.delaysTouchesEnded = false
            
            action.view.addGestureRecognizer(tapper)
            
            actionsView.addArrangedSubview(action.view)
        }
        
        // Always retain natural row heights. A short/resized window scrolls even
        // when the menu has fewer actions than the normal scrolling threshold.
        let scrollView = UIScrollView()
        actionsScrollView = scrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = !appearance.popMenuScrollIndicatorHidden
        scrollView.indicatorStyle = appearance.popMenuScrollIndicatorStyle
        scrollView.addSubview(actionsView)
        contentView.addSubview(scrollView)
        actionsView.addGestureRecognizer(panGestureForMenu)
        NSLayoutConstraint.activate([
            scrollView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionsView.leftAnchor.constraint(equalTo: scrollView.leftAnchor),
            actionsView.rightAnchor.constraint(equalTo: scrollView.rightAnchor),
            actionsView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            actionsView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            actionsView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            actionsView.heightAnchor.constraint(equalToConstant: appearance.popMenuActionHeight * CGFloat(actions.count))
        ])
    }
    
    /// Add separator view for the given action view.
    ///
    /// - Parameters:
    ///   - separator: Separator style
    ///   - actionView: Action's view
    fileprivate func addSeparator(to actionView: UIView) {
        // Only setup separator if the style is neither 0 height or clear color
        guard appearance.popMenuItemSeparator != .none() else { return }
        
        let separator = appearance.popMenuItemSeparator
        
        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = separator.color
        
        actionView.addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            separatorView.leftAnchor.constraint(equalTo: actionView.leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: actionView.rightAnchor),
            separatorView.bottomAnchor.constraint(equalTo: actionView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: separator.height)
        ])
    }
    
}

// MARK: - Gestures Control

extension PopMenuViewController {

    /// Once the background view is tapped (for dismissal).
    @objc fileprivate func backgroundViewDidTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.isEqual(tapGestureForDismissal), !touchedInsideContent(location: gesture.location(in: view)) else { return }
        
        dismiss(animated: true) {
            // No selection made.
            self.didDismiss?(false)
        }
    }
    
    /// When the menu action gets tapped.
    @objc fileprivate func menuDidTap(_ gesture: UITapGestureRecognizer) {
        guard let attachedView = gesture.view, let index = actions.index(where: { $0.view.isEqual(attachedView) }) else { return }

        actionDidSelect(at: index)
    }
    
    /// When the pan gesture triggered in actions view.
    @objc fileprivate func menuDidPan(_ gesture: UIPanGestureRecognizer) {
        guard shouldEnablePanGesture else { return }
        
        switch gesture.state {
        case .began, .changed:
            if let index = associatedActionIndex(gesture) {
                let action = actions[index]
                // Must not be already highlighted
                guard !action.highlighted else { return }
                
                if shouldEnableHaptics {
                    Haptic.selection.generate()
                }
                
                // Highlight current action view.
                action.highlighted = true
                // Unhighlight other actions.
                actions.filter { return !$0.isEqual(action) }.forEach { $0.highlighted = false }
            }
        case .ended:
            // Unhighlight all actions.
            actions.filter { return $0.highlighted }.forEach { $0.highlighted = false }
            // Trigger action selection.
            if let index = associatedActionIndex(gesture) {
                actionDidSelect(at: index, animated: false)
            }
        default:
            return
        }
    }
    
    /// Check if touch is inside content view.
    fileprivate func touchedInsideContent(location: CGPoint) -> Bool {
        return containerView.frame.contains(location)
    }
    
    ///  Get the gesture associated action index.
    ///
    /// - Parameter gesture: Gesture recognizer
    /// - Returns: The index
    fileprivate func associatedActionIndex(_ gesture: UIGestureRecognizer) -> Int? {
        guard touchedInsideContent(location: gesture.location(in: view)) else { return nil }
        
        // Check which action is associated.
        let touchLocation = gesture.location(in: actionsView)
        // Get associated index for touch location.
        if let touchedView = actionsView.arrangedSubviews.filter({ return $0.frame.contains(touchLocation) }).first,
            let index = actionsView.arrangedSubviews.index(of: touchedView){
            return index
        }
        
        return nil
    }
    
    /// Triggers when an action is selected.
    ///
    /// - Parameter index: The index for action
    fileprivate func actionDidSelect(at index: Int, animated: Bool = true) {
        let action = actions[index]
        action.actionSelected?(animated: animated)
        
        if shouldEnableHaptics {
            // Generate haptics
            if #available(iOS 10.0, *) {
                Haptic.impact(.medium).generate()
            }
        }
        
        // Notify delegate
        delegate?.popMenuDidSelectItem?(self, at: index)
        
        // Should dismiss or not
        if shouldDismissOnSelection {
            dismiss(animated: true) {
                // Selection made.
                self.didDismiss?(true)
            }
        }
    }
    
}

// MARK: - Transitioning Delegate

extension PopMenuViewController: UIViewControllerTransitioningDelegate {
    
    /// Custom presentation animation.
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PopMenuPresentAnimationController(sourceFrame: absoluteSourceFrame)
    }
    
    /// Custom dismissal animation.
    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PopMenuDismissAnimationController(sourceFrame: absoluteSourceFrame)
    }

}
