import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import "package:logging/logging.dart";
import 'package:photos/ui/common/loading_widget.dart';
import "package:url_launcher/url_launcher_string.dart";

class WebPage extends StatefulWidget {
  final String title;
  final String url;

  // if true, show open in browser  icon in appBar
  final bool canOpenInBrowser;

  const WebPage(
    this.title,
    this.url, {
    super.key,
    this.canOpenInBrowser = false,
  });

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  bool _hasLoadedPage = false;
  final Logger _logger = Logger('_WebPageState');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // force dark theme for appBar till website/family plans add supports for light theme
        backgroundColor: const Color.fromRGBO(10, 20, 20, 1.0),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title),
        actions: [
          _hasLoadedPage
              ? (widget.canOpenInBrowser
                    ? IconButton(
                        icon: const Icon(Icons.open_in_browser_outlined),
                        color: Colors.white,
                        onPressed: () {
                          try {
                            launchUrlString(
                              widget.url,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            _logger.severe("Failed to pop web page", e);
                          }
                        },
                      )
                    : const SizedBox.shrink())
              : const EnteLoadingWidget(color: Colors.white, padding: 12),
        ],
      ),
      backgroundColor: Colors.black,
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(transparentBackground: true),
        onLoadStop: (c, url) {
          setState(() {
            _hasLoadedPage = true;
          });
        },
      ),
    );
  }
}
