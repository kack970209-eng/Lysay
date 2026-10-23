import SwiftUI
import UIKit

/// 让 playInputClick() 发出系统键盘音
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    override func loadView() {
        let v = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        view = v
        inputView = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self

        let hc = UIHostingController(rootView: KeyboardRootView(model: model))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            hc.safeAreaRegions = []
        }
        addChild(hc)
        view.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hc.didMove(toParent: self)
        host = hc

        let h = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.height)
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightConstraint = h
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.needsGlobe = needsInputModeSwitchKey
        updateReturnTitle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.keyboardDidAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.keyboardWillDisappear()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnTitle()
    }

    private func updateReturnTitle() {
        let title: String
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: title = "前往"
        case .search, .google, .yahoo: title = "搜索"
        case .send: title = "发送"
        case .done: title = "完成"
        case .next: title = "下一项"
        case .join: title = "加入"
        case .route: title = "路线"
        default: title = "换行"
        }
        model.returnTitle = title
    }

    /// 键盘扩展不能直接调用 UIApplication.shared.open，
    /// 这里沿响应链找到 UIApplication 实例，用运行时调用打开主 App。
    func openMainApp() {
        let url = LysayIPC.dictateURL
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication, app.responds(to: selector) {
                typealias OpenFn = @convention(c) (AnyObject, Selector, URL, NSDictionary, AnyObject?) -> Void
                let imp = app.method(for: selector)
                let fn = unsafeBitCast(imp, to: OpenFn.self)
                fn(app, selector, url, NSDictionary(), nil)
                return
            }
            responder = r.next
        }
        // 兜底：通过 extensionContext 打开（部分宿主可用）
        extensionContext?.open(url, completionHandler: nil)
    }
}
