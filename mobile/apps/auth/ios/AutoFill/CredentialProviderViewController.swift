import AuthenticationServices
import LocalAuthentication
import UIKit

@available(iOS 18.0, *)
final class CredentialProviderViewController: ASCredentialProviderViewController,
    UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private var snapshot: AutoFillSnapshot?
    private var entries: [AutoFillEntry] = []
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchController(searchResultsController: nil)
    private var authentication: LAContext?
    private var isAuthenticating = false
    private var finished = false
    private var pendingRequest: (any ASCredentialRequest)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let controller = UIViewController()
        controller.title = "Ente Auth"
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        controller.navigationItem.searchController = search
        controller.navigationItem.hidesSearchBarWhenScrolling = false
        table.dataSource = self
        table.delegate = self
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view = table
        let navigation = UINavigationController(rootViewController: controller)
        addChild(navigation)
        navigation.view.frame = view.bounds
        navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cancel),
            name: .NSExtensionHostDidEnterBackground, object: nil
        )
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        pendingRequest = nil
        loadViewIfNeeded()
    }

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain, code: ASExtensionError.Code.userInteractionRequired.rawValue
        ))
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        pendingRequest = credentialRequest
        loadViewIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard snapshot == nil, !isAuthenticating, !finished else { return }
        isAuthenticating = true
        let context = LAContext()
        authentication = context
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock Ente Auth verification codes") { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                self.isAuthenticating = false
                guard success else { self.cancel(); return }
                do {
                    self.snapshot = try AutoFillStore.read()
                    if let request = self.pendingRequest as? ASOneTimeCodeCredentialRequest,
                       let id = request.credentialIdentity.recordIdentifier,
                       let entry = self.snapshot?.entries.first(where: { $0.id == id }) {
                        self.fill(entry)
                    } else {
                        self.updateSearchResults(for: self.search)
                    }
                } catch {
                    self.showMessage("Open Ente Auth and enable AutoFill in General settings to make your codes available.")
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        entries = (snapshot?.entries ?? []).filter {
            query.isEmpty || "\($0.issuer) \($0.account)".localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
        if entries.isEmpty {
            showMessage(query.isEmpty ? "No TOTP codes available. Open Ente Auth to update AutoFill." : "No matching accounts.")
        } else {
            table.backgroundView = nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let entry = entries[indexPath.row]
        cell.textLabel?.text = entry.issuer.isEmpty ? entry.account : entry.issuer
        cell.detailTextLabel?.text = entry.account
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !finished, entries.indices.contains(indexPath.row) else { return }
        fill(entries[indexPath.row])
    }

    private func fill(_ entry: AutoFillEntry) {
        do {
            // Re-read so deletion, logout or disabling AutoFill invalidates an open picker.
            let current = try AutoFillStore.read()
            guard let entry = current.entries.first(where: { $0.id == entry.id }) else {
                throw AutoFillStore.StoreError.invalidSnapshot
            }
            let time = Date().timeIntervalSince1970 + Double(current.timeOffsetMilliseconds) / 1000
            let code = try TOTP.generate(entry, time: time)
            finished = true
            snapshot = nil
            entries = []
            table.reloadData()
            extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code))
        } catch {
            snapshot = nil
            entries = []
            table.reloadData()
            showMessage("This code is no longer available. Open Ente Auth to update AutoFill.")
        }
    }

    private func showMessage(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        table.backgroundView = label
    }

    @objc private func cancel() {
        guard !finished else { return }
        finished = true
        authentication?.invalidate()
        snapshot = nil
        entries = []
        table.reloadData()
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain, code: ASExtensionError.Code.userCanceled.rawValue
        ))
    }
}
