import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
