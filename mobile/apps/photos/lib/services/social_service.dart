import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:nanoid/nanoid.dart';
import 'package:photos/models/social/api_responses.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';

class SocialService {
  SocialService._();
  static final instance = SocialService._();

  final _logger = Logger('SocialService');

  static const _commentIDLength = 21;
  static const _reactionIDLength = 21;
  static const _commentPrefix = 'cmt_';
  static const _reactionPrefix = 'rct_';
  static const _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  // Fixed-length padding keeps reaction ciphertexts the same size.
  static const _reactionPadLength = 100;

  String generateCommentID() {
    return '$_commentPrefix${customAlphabet(_alphabet, _commentIDLength)}';
  }

  String generateReactionID() {
    return '$_reactionPrefix${customAlphabet(_alphabet, _reactionIDLength)}';
  }

  Future<String> createComment({
    required int collectionID,
    required String cipher,
    required String nonce,
    int? fileID,
    String? parentCommentID,
    String? id,
  }) async {
    final commentID = id ?? generateCommentID();
    return socialGateway.createComment(
      id: commentID,
      collectionID: collectionID,
      cipher: cipher,
      nonce: nonce,
      fileID: fileID,
      parentCommentID: parentCommentID,
    );
  }

  Future<void> updateComment({
    required String commentID,
    required String cipher,
    required String nonce,
  }) async {
    return socialGateway.updateComment(
      commentID: commentID,
      cipher: cipher,
      nonce: nonce,
    );
  }

  Future<void> deleteComment(String commentID) async {
    return socialGateway.deleteComment(commentID);
  }

  Future<CommentsDiffResponse> fetchCommentsDiff({
    required int collectionID,
    int? sinceTime,
    int? limit,
    int? fileID,
  }) async {
    return socialGateway.fetchCommentsDiff(
      collectionID: collectionID,
      sinceTime: sinceTime,
      limit: limit,
      fileID: fileID,
    );
  }

  Future<String> upsertReaction({
    required int collectionID,
    required String cipher,
    required String nonce,
    int? fileID,
    String? commentID,
    String? id,
  }) async {
    final reactionID = id ?? generateReactionID();
    return socialGateway.upsertReaction(
      id: reactionID,
      collectionID: collectionID,
      cipher: cipher,
      nonce: nonce,
      fileID: fileID,
      commentID: commentID,
    );
  }

  Future<void> deleteReaction(String reactionID) async {
    return socialGateway.deleteReaction(reactionID);
  }

  Future<ReactionsDiffResponse> fetchReactionsDiff({
    required int collectionID,
    int? sinceTime,
    int? limit,
    int? fileID,
    String? commentID,
  }) async {
    return socialGateway.fetchReactionsDiff(
      collectionID: collectionID,
      sinceTime: sinceTime,
      limit: limit,
      fileID: fileID,
      commentID: commentID,
    );
  }

  Future<LatestUpdatesResponse> fetchLatestUpdates() async {
    return socialGateway.fetchLatestUpdates();
  }

  Future<AnonProfilesResponse> fetchAnonProfiles(int collectionID) async {
    return socialGateway.fetchAnonProfiles(collectionID);
  }

  Future<SocialDiffResponse> fetchSocialDiff({
    required int collectionID,
    int? commentsSinceTime,
    int? reactionsSinceTime,
    int? limit,
    int? fileID,
  }) async {
    return socialGateway.fetchSocialDiff(
      collectionID: collectionID,
      commentsSinceTime: commentsSinceTime,
      reactionsSinceTime: reactionsSinceTime,
      limit: limit,
      fileID: fileID,
    );
  }

  Future<Map<int, int>> fetchCounts() async {
    return socialGateway.fetchCounts();
  }

  ({String cipher, String nonce}) encryptComment(
    String text,
    int collectionID,
  ) {
    final collectionKey = CollectionsService.instance.getCollectionKey(
      collectionID,
    );
    final textBytes = utf8.encode(text);

    final encrypted = CryptoUtil.encryptSync(
      Uint8List.fromList(textBytes),
      collectionKey,
    );

    return (
      cipher: CryptoUtil.bin2base64(encrypted.encryptedData!),
      nonce: CryptoUtil.bin2base64(encrypted.nonce!),
    );
  }

  // Returns an empty string when decryption fails.
  String decryptComment(String? cipher, String? nonce, int collectionID) {
    if (cipher == null || nonce == null || cipher.isEmpty || nonce.isEmpty) {
      return '';
    }

    try {
      final collectionKey = CollectionsService.instance.getCollectionKey(
        collectionID,
      );
      final cipherBytes = CryptoUtil.base642bin(cipher);
      final nonceBytes = CryptoUtil.base642bin(nonce);

      final decrypted = CryptoUtil.decryptSync(
        cipherBytes,
        collectionKey,
        nonceBytes,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      _logger.warning('Failed to decrypt comment', e);
      return '';
    }
  }

  ({String cipher, String nonce}) encryptReaction(
    String reactionType,
    int collectionID,
  ) {
    final collectionKey = CollectionsService.instance.getCollectionKey(
      collectionID,
    );

    final padded = _padReactionType(reactionType);
    final paddedBytes = utf8.encode(padded);

    final encrypted = CryptoUtil.encryptSync(
      Uint8List.fromList(paddedBytes),
      collectionKey,
    );

    return (
      cipher: CryptoUtil.bin2base64(encrypted.encryptedData!),
      nonce: CryptoUtil.bin2base64(encrypted.nonce!),
    );
  }

  // Returns an empty string when decryption fails.
  String decryptReaction(String? cipher, String? nonce, int collectionID) {
    if (cipher == null || nonce == null || cipher.isEmpty || nonce.isEmpty) {
      return '';
    }

    try {
      final collectionKey = CollectionsService.instance.getCollectionKey(
        collectionID,
      );
      final cipherBytes = CryptoUtil.base642bin(cipher);
      final nonceBytes = CryptoUtil.base642bin(nonce);

      final decrypted = CryptoUtil.decryptSync(
        cipherBytes,
        collectionKey,
        nonceBytes,
      );

      final decoded = utf8.decode(decrypted);
      return _unpadReactionType(decoded);
    } catch (e) {
      _logger.warning('Failed to decrypt reaction', e);
      return '';
    }
  }

  String _padReactionType(String reactionType) {
    if (reactionType.length >= _reactionPadLength) {
      return reactionType.substring(0, _reactionPadLength);
    }
    return reactionType.padRight(_reactionPadLength, '\x00');
  }

  String _unpadReactionType(String padded) {
    final nullIndex = padded.indexOf('\x00');
    if (nullIndex == -1) {
      return padded;
    }
    return padded.substring(0, nullIndex);
  }

  // Returns an empty string when decryption fails.
  String decryptAnonProfile(String? cipher, String? nonce, int collectionID) {
    if (cipher == null || nonce == null || cipher.isEmpty || nonce.isEmpty) {
      return '';
    }

    try {
      final collectionKey = CollectionsService.instance.getCollectionKey(
        collectionID,
      );
      final cipherBytes = CryptoUtil.base642bin(cipher);
      final nonceBytes = CryptoUtil.base642bin(nonce);

      final decrypted = CryptoUtil.decryptSync(
        cipherBytes,
        collectionKey,
        nonceBytes,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      _logger.warning('Failed to decrypt anon profile', e);
      return '';
    }
  }
}
