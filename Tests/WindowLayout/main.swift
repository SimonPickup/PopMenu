import UIKit
import Foundation

// A full UIKit process without UIApplicationMain or any visible/native window.
// The sole SDK-boundary fixture supplies otherwise OS-owned safe-area insets.
final class FixtureRootView: UIView {
    private let fixtureGuide = UILayoutGuide()
    private var guideConstraints: [NSLayoutConstraint] = []
    var fixtureInsets = UIEdgeInsets.zero {
        didSet {
            guard guideConstraints.count == 4 else { return }
            guideConstraints[0].constant = fixtureInsets.left
            guideConstraints[1].constant = -fixtureInsets.right
            guideConstraints[2].constant = fixtureInsets.top
            guideConstraints[3].constant = -fixtureInsets.bottom
        }
    }
    override var safeAreaInsets: UIEdgeInsets { fixtureInsets }
    override var safeAreaLayoutGuide: UILayoutGuide { fixtureGuide }
    override init(frame: CGRect) {
        super.init(frame: frame)
        addLayoutGuide(fixtureGuide)
        guideConstraints = [fixtureGuide.leadingAnchor.constraint(equalTo: leadingAnchor),fixtureGuide.trailingAnchor.constraint(equalTo: trailingAnchor),fixtureGuide.topAnchor.constraint(equalTo: topAnchor),fixtureGuide.bottomAnchor.constraint(equalTo: bottomAnchor)]
        NSLayoutConstraint.activate(guideConstraints)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}
var passed = 0
var failed = 0
func check(_ condition: Bool, _ name: String, _ detail: String = "") {
    if condition { passed += 1; print("PASS \(name) \(detail)") }
    else { failed += 1; print("FAIL \(name) \(detail)") }
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a-b) < 0.6 }
func same(_ a: CGRect, _ b: CGRect) -> Bool {
    near(a.minX,b.minX) && near(a.minY,b.minY) && near(a.width,b.width) && near(a.height,b.height)
}
func inside(_ frame: CGRect, _ bounds: CGRect) -> Bool {
    frame.minX >= bounds.minX-0.6 && frame.minY >= bounds.minY-0.6 && frame.maxX <= bounds.maxX+0.6 && frame.maxY <= bounds.maxY+0.6
}
func layout(_ menu: PopMenuViewController) {
    // Explicit controller callback delivery: no UIApplication/scene lifecycle is running.
    menu.viewWillLayoutSubviews()
    menu.view.setNeedsLayout()
    menu.view.layoutIfNeeded()
    menu.viewDidLayoutSubviews()
    menu.view.layoutIfNeeded()
}
func actions(_ count: Int = 3, long: Bool = false) -> [PopMenuAction] {
    (0..<count).map { PopMenuDefaultAction(title: long ? String(repeating: "Wide title ", count: 30) : "Action \($0)") }
}
print("REAL UIKit Catalyst full-source regression; main thread=\(Thread.isMainThread)")
let common = UIView(frame: CGRect(x:0,y:0,width:1000,height:800))
let child = UIView(frame: CGRect(x:30,y:40,width:50,height:60))
common.addSubview(child)
check(same(child.convert(child.bounds,to:common),child.frame), "UIKit coordinate control")
let fill = UIView()
fill.translatesAutoresizingMaskIntoConstraints = false
common.addSubview(fill)
NSLayoutConstraint.activate([fill.leadingAnchor.constraint(equalTo: common.leadingAnchor),fill.trailingAnchor.constraint(equalTo: common.trailingAnchor),fill.topAnchor.constraint(equalTo: common.topAnchor),fill.bottomAnchor.constraint(equalTo: common.bottomAnchor)])
common.layoutIfNeeded()
check(same(fill.frame,common.bounds), "UIKit Auto Layout control")

let menu = PopMenuViewController(actions: actions())
menu.loadViewIfNeeded() // Unmodified production loadView/configuration path.
common.addSubview(menu.view)
menu.view.frame = CGRect(x:75,y:90,width:320,height:240)
layout(menu)
check(same(menu.backgroundView.frame,menu.view.bounds),"dim fills initial host bounds","actual=\(menu.backgroundView.frame) expected=\(menu.view.bounds)")
check(inside(menu.containerView.frame,menu.view.bounds),"content inside initial host bounds","actual=\(menu.containerView.frame)")
menu.view.frame = CGRect(x:75,y:90,width:640,height:420)
layout(menu)
check(same(menu.backgroundView.frame,menu.view.bounds),"dim fills resized host bounds","actual=\(menu.backgroundView.frame) expected=\(menu.view.bounds)")
check(inside(menu.containerView.frame,menu.view.bounds),"content inside resized host bounds","actual=\(menu.containerView.frame)")
let dimCount = menu.view.subviews.filter { $0 === menu.backgroundView }.count
check(dimCount == 1,"single retained dim view")

let sourceParent = UIView(frame:CGRect(x:140,y:150,width:400,height:300))
common.addSubview(sourceParent)
let source = UIView(frame:CGRect(x:80,y:65,width:44,height:30))
sourceParent.addSubview(source)
let anchored = PopMenuViewController(sourceView:source, actions:actions())
anchored.loadViewIfNeeded()
common.addSubview(anchored.view)
anchored.view.frame = CGRect(x:75,y:90,width:320,height:240)
layout(anchored)
let expectedSource = source.convert(source.bounds,to:anchored.view)
check(anchored.absoluteSourceFrame.map { same($0,expectedSource) } ?? false,"source converts into menu coordinate space","actual=\(String(describing:anchored.absoluteSourceFrame)) expected=\(expectedSource)")
source.frame.origin = CGPoint(x:100,y:85)
layout(anchored)
let movedSource = source.convert(source.bounds,to:anchored.view)
check(anchored.absoluteSourceFrame.map { same($0,movedSource) } ?? false,"source conversion refreshes after layout","actual=\(String(describing:anchored.absoluteSourceFrame)) expected=\(movedSource)")
check(inside(anchored.containerView.frame,anchored.view.bounds),"anchored content inside host bounds","actual=\(anchored.containerView.frame)")

let safeRoot = FixtureRootView(frame:CGRect(x:40,y:50,width:240,height:180))
safeRoot.fixtureInsets = UIEdgeInsets(top:24,left:18,bottom:32,right:22)
let safeMenu = PopMenuViewController(actions:actions(12,long:true))
safeMenu.harnessInstallRoot(safeRoot)
common.addSubview(safeRoot)
layout(safeMenu)
let safeBounds = safeRoot.bounds.inset(by:safeRoot.safeAreaInsets)
check(safeRoot.safeAreaInsets.top == 24,"scripted safe-area boundary control","insets=\(safeRoot.safeAreaInsets)")
check(same(safeRoot.safeAreaLayoutGuide.layoutFrame,safeBounds),"real UIKit safe-area guide fixture control","actual=\(safeRoot.safeAreaLayoutGuide.layoutFrame) expected=\(safeBounds)")
check(inside(safeMenu.containerView.frame,safeBounds),"wide tall content stays in nonzero safe bounds","actual=\(safeMenu.containerView.frame) expectedWithin=\(safeBounds)")
safeRoot.frame.size = CGSize(width:180,height:140)
layout(safeMenu)
check(inside(safeMenu.containerView.frame,safeRoot.bounds.inset(by:safeRoot.safeAreaInsets)),"content stays safe after shrink","actual=\(safeMenu.containerView.frame) expectedWithin=\(safeRoot.bounds.inset(by:safeRoot.safeAreaInsets))")
// Exercise repeated native layout, scrolling, blur fill and the actual animator.
let stableConstraintCount = menu.view.constraints.count
for size in [CGSize(width: 900, height: 700), CGSize(width: 240, height: 120), CGSize(width: 640, height: 420)] {
    menu.view.frame.size = size
    layout(menu)
    check(same(menu.backgroundView.frame, menu.view.bounds), "backdrop tracks repeated resize")
    check(menu.view.constraints.count == stableConstraintCount, "resize does not accumulate constraints")
}
let shortMenu = PopMenuViewController(actions: actions(3))
shortMenu.loadViewIfNeeded()
common.addSubview(shortMenu.view)
shortMenu.view.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
layout(shortMenu)
let shortScroll = shortMenu.contentView.subviews.compactMap { $0 as? UIScrollView }.first
check(shortScroll?.isScrollEnabled == true, "short menu enables scrolling below count threshold")
check(near(shortScroll?.contentSize.height ?? 0, 150), "scroll retains natural action row heights")
check(near(shortMenu.actionsView.arrangedSubviews.last?.frame.maxY ?? 0, 150), "last action remains in scrollable content")
shortMenu.view.frame.size.height = 400
layout(shortMenu)
check(shortScroll?.isScrollEnabled == false, "scroll disables again when rows fit")
check(menu.view.hitTest(CGPoint(x: 1, y: 1), with: nil) === menu.backgroundView, "outside-menu native hit test reaches full backdrop")
var blurAppearance = PopMenuAppearance()
blurAppearance.popMenuBackgroundStyle = .blurred(.dark)
let blurred = PopMenuViewController(actions: actions(), appearance: blurAppearance)
blurred.loadViewIfNeeded()
common.addSubview(blurred.view)
blurred.view.frame = CGRect(x: 10, y: 20, width: 720, height: 480)
layout(blurred)
check(blurred.backgroundView.subviews.first.map { same($0.frame, blurred.view.bounds) } ?? false, "blur effect fills backdrop")
let lastAttachedAnchor = anchored.absoluteSourceFrame
source.removeFromSuperview()
layout(anchored)
check(anchored.absoluteSourceFrame == lastAttachedAnchor, "previously resolved anchor survives source detachment")
check(inside(anchored.containerView.frame, anchored.view.bounds), "detached retained anchor remains inside local bounds")

final class Transition: NSObject, UIViewControllerContextTransitioning {
    let containerView: UIView
    let menu: PopMenuViewController
    var completed: Bool?
    var isAnimated: Bool { true }
    var isInteractive: Bool { false }
    var transitionWasCancelled: Bool { false }
    var presentationStyle: UIModalPresentationStyle { .overFullScreen }
    var targetTransform: CGAffineTransform { .identity }
    init(_ container: UIView, _ menu: PopMenuViewController) { self.containerView = container; self.menu = menu }
    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() {}
    func pauseInteractiveTransition() {}
    func completeTransition(_ didComplete: Bool) { completed = didComplete }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { menu }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { menu.view }
    func initialFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
}
sourceParent.addSubview(source)
let transitionContainer = UIView(frame: CGRect(x: 90, y: 70, width: 800, height: 600))
common.addSubview(transitionContainer)
let presented = PopMenuViewController(sourceView: source, actions: actions(7))
let context = Transition(transitionContainer, presented)
UIView.setAnimationsEnabled(false)
let animator = presented.animationController(forPresented: presented, presenting: UIViewController(), source: UIViewController())!
animator.animateTransition(using: context)
layout(presented)
check(same(presented.view.frame, transitionContainer.bounds), "animator uses local final presentation frame")
check(same(presented.backgroundView.frame, presented.view.bounds), "animator backdrop fills final presentation")
check(same(presented.containerView.frame, presented.contentFrame), "animator reaches final content constraints")
check(presented.absoluteSourceFrame.map { same($0, source.convert(source.bounds, to: presented.view)) } ?? false, "animator resolves source after attachment")
let dismiss = presented.animationController(forDismissed: presented)!
dismiss.animateTransition(using: context)
check(same(presented.view.frame, transitionContainer.bounds), "dismiss animator stays in local bounds")
UIView.setAnimationsEnabled(true)
presented.view.removeFromSuperview()
let submenu = PopMenuViewController(sourceView: source, actions: actions(2))
submenu.loadViewIfNeeded()
common.addSubview(submenu.view)
submenu.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
layout(submenu)
check(submenu.absoluteSourceFrame.map { same($0, source.convert(source.bounds, to: submenu.view)) } ?? false,
      "submenu keeps original source anchor after parent menu detaches")
let tapped = PopMenuViewController(sourceView: source, sourcePoint: CGPoint(x: 7, y: 9), actions: actions(2))
tapped.loadViewIfNeeded()
common.addSubview(tapped.view)
tapped.view.frame = CGRect(x: 75, y: 90, width: 640, height: 420)
layout(tapped)
let expectedTap = source.convert(CGPoint(x: 7, y: 9), to: tapped.view)
check(tapped.absoluteSourceFrame.map { same($0, CGRect(origin: expectedTap, size: .zero)) } ?? false,
      "tap point converts from bubble to presentation coordinates")
check(near(tapped.containerView.frame.minX, expectedTap.x + 8) && near(tapped.containerView.frame.minY, expectedTap.y + 8),
      "tap point places menu beside the interaction rather than bubble centre")
let pointPresentation = PopMenuViewController(sourceView: source, sourcePoint: CGPoint(x: 7, y: 9), actions: actions(2))
let pointContext = Transition(transitionContainer, pointPresentation)
UIView.setAnimationsEnabled(false)
pointPresentation.animationController(forPresented: pointPresentation, presenting: UIViewController(), source: UIViewController())!.animateTransition(using: pointContext)
layout(pointPresentation)
check(same(pointPresentation.containerView.frame, pointPresentation.contentFrame), "tap-point animation reaches final content frame without collapsing rows")
UIView.setAnimationsEnabled(true)
let corner = PopMenuViewController(sourceView: common, sourcePoint: CGPoint(x: 990, y: 790), actions: actions(7))
corner.loadViewIfNeeded()
common.addSubview(corner.view)
corner.view.frame = common.bounds
layout(corner)
check(inside(corner.containerView.frame, corner.view.bounds), "tap point near corner retains existing edge clamping")
let zero = PopMenuViewController(sourceView: source, sourcePoint: .zero, actions: actions(2))
zero.loadViewIfNeeded()
common.addSubview(zero.view)
zero.view.frame = common.bounds
layout(zero)
check(zero.absoluteSourceFrame?.size == .zero, "zero-coordinate tap is a real point, not missing input")
let fallback = PopMenuViewController(sourceView: source, actions: actions(2))
fallback.loadViewIfNeeded()
common.addSubview(fallback.view)
fallback.view.frame = common.bounds
layout(fallback)
let fallbackRect = source.convert(source.bounds, to: fallback.view)
check(fallback.absoluteSourceFrame.map { same($0, fallbackRect) } ?? false, "missing point falls back to bubble bounds")
check(near(fallback.containerView.frame.midX, fallbackRect.midX), "bubble fallback retains existing centring")

print("RESULT passed=\(passed) failed=\(failed)")
exit(failed == 0 ? 0 : 1)
