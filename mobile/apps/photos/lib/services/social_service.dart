import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:nanoid/nanoid.dart';
import 'package:photos/models/social/api_responses.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';

/// Service for social features (comments and reactions).
///
/// Handles API calls and encryption/decryption using collection keys.
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

  /// Reaction type padding length before encryption.
  /// Ensures all encrypted reactions have the same ciphertext length.
  static const _reactionPadLength = 100;

  /// Generates a new comment ID in the format: cmt_ + 21 char nanoid
  String generateCommentID() {
    return '$_commentPrefix${customAlphabet(_alphabet, _commentIDLength)}';
  }

  /// Generates a new reaction ID in the format: rct_ + 21 char nanoid
  String generateReactionID() {
    return '$_reactionPrefix${customAlphabet(_alphabet, _reactionIDLength)}';
  }

  // ============ Comments API ============

  /// Creates a new comment on the server.
  ///
  /// [collectionID] - The collection this comment belongs to
  /// [cipher] - The encrypted comment text (base64)
  /// [nonce] - The encryption nonce (base64)
  /// [fileID] - Optional file ID if commenting on a file
  /// [parentCommentID] - Optional parent comment ID for replies
  /// [id] - Optional comment ID; generated if not provided
  ///
  /// Returns the comment ID (server-assigned or the provided one)
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

  /// Updates an existing comment.
  ///
  /// [commentID] - The comment ID to update
  /// [cipher] - The new encrypted comment text (base64)
  /// [nonce] - The new encryption nonce (base64)
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

  /// Deletes a comment (soft delete on server).
  Future<void> deleteComment(String commentID) async {
    return socialGateway.deleteComment(commentID);
  }

  /// Fetches comments diff for a collection.
  ///
  /// [collectionID] - The collection to fetch comments from
  /// [sinceTime] - Only fetch comments updated after this timestamp
  /// [limit] - Maximum number of comments to fetch (default 1000, max 2000)
  /// [fileID] - Optional filter for comments on a specific file
  ///
  /// Returns [CommentsDiffResponse] with comments and hasMore flag
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

  // ============ Reactions API ============

  /// Creates or updates a reaction (upsert).
  ///
  /// [collectionID] - The collection this reaction belongs to
  /// [cipher] - The encrypted reaction type (base64, exactly 156 bytes)
  /// [nonce] - The encryption nonce (base64)
  /// [fileID] - Optional file ID if reacting to a file
  /// [commentID] - Optional comment ID if reacting to a comment
  /// [id] - Optional reaction ID; generated if not provided
  ///
  /// Returns the reaction ID
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

  /// Deletes a reaction (soft delete on server).
  Future<void> deleteReaction(String reactionID) async {
    return socialGateway.deleteReaction(reactionID);
  }

  /// Fetches reactions diff for a collection.
  ///
  /// [collectionID] - The collection to fetch reactions from
  /// [sinceTime] - Only fetch reactions updated after this timestamp
  /// [limit] - Maximum number of reactions to fetch (default 1000, max 2000)
  /// [fileID] - Optional filter for reactions on a specific file
  /// [commentID] - Optional filter for reactions on a specific comment
  ///
  /// Returns [ReactionsDiffResponse] with reactions and hasMore flag
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

  // ============ Latest Updates API ============

  /// Fetches latest update timestamps for all collections accessible to the
  /// user.
  ///
  /// Returns per-collection timestamps for comments, reactions, and anonymous
  /// profiles. Use this to determine which collections need syncing.
  Future<LatestUpdatesResponse> fetchLatestUpdates() async {
    return socialGateway.fetchLatestUpdates();
  }

  /// Fetches anonymous profiles for a collection.
  ///
  /// Returns encrypted profile data that needs to be decrypted with the
  /// collection key.
  Future<AnonProfilesResponse> fetchAnonProfiles(int collectionID) async {
    return socialGateway.fetchAnonProfiles(collectionID);
  }

  // ============ Unified/Social API ============

  /// Fetches both comments and reactions in a single call.
  ///
  /// [collectionID] - The collection to fetch social data from
  /// [commentsSinceTime] - Only fetch comments updated after this timestamp
  /// [reactionsSinceTime] - Only fetch reactions updated after this timestamp
  /// [limit] - Maximum number of items per type (default 1000, max 2000)
  /// [fileID] - Optional filter for items on a specific file
  ///
  /// Returns [SocialDiffResponse] with comments, reactions, and hasMore flags
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

  /// Fetches comment and reaction counts for all collections.
  ///
  /// Returns a map of collectionID -> count
  Future<Map<int, int>> fetchCounts() async {
    return socialGateway.fetchCounts();
  }

  // ============ Encryption/Decryption ============

  /// Encrypts comment text with the collection key.
  ///
  /// Returns a record of (cipher, nonce) as base64 strings.
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

  /// Decrypts comment cipher to plaintext.
  ///
  /// Returns the decrypted text, or empty string if decryption fails.
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

  /// Encrypts reaction type with the collection key.
  ///
  /// The reaction type is padded to fixed length before encryption,
  /// ensuring consistent ciphertext length.
  ({String cipher, String nonce}) encryptReaction(
    String reactionType,
    int collectionID,
  ) {
    final collectionKey = CollectionsService.instance.getCollectionKey(
      collectionID,
    );

    // Pad reaction type to fixed length
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

  /// Decrypts reaction cipher to reaction type.
  ///
  /// Returns the decrypted reaction type (with padding removed),
  /// or empty string if decryption fails.
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

      // Remove null byte padding
      final decoded = utf8.decode(decrypted);
      return _unpadReactionType(decoded);
    } catch (e) {
      _logger.warning('Failed to decrypt reaction', e);
      return '';
    }
  }

  /// Pads a reaction type to fixed length with null bytes.
  String _padReactionType(String reactionType) {
    if (reactionType.length >= _reactionPadLength) {
      return reactionType.substring(0, _reactionPadLength);
    }
    return reactionType.padRight(_reactionPadLength, '\x00');
  }

  /// Removes null byte padding from reaction type.
  String _unpadReactionType(String padded) {
    final nullIndex = padded.indexOf('\x00');
    if (nullIndex == -1) {
      return padded;
    }
    return padded.substring(0, nullIndex);
  }

  /// Decrypts anonymous profile data.
  ///
  /// Returns the decrypted display-name string, or empty string if decryption
  /// fails.
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
