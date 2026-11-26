import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../reading/data/reading_vocab_lists.dart';
import '../../reading/domain/reading_doc.dart';

const int kReadingBackupMaxBytes = 16 * 1024 * 1024;

class ReadingLibrarySnapshot {
  const ReadingLibrarySnapshot({
    required this.docs,
    required this.progress,
    required this.vocabLists,
  });

  final List<ReadingDoc> docs;
  final Map<String, ReadingProgress> progress;
  final ReadingVocabLists vocabLists;

  Map<String, dynamic> toStateJson() => <String, dynamic>{
    'version': 1,
    'docs': docs.map((ReadingDoc d) => d.toJson()).toList(),
    'progress': <String, Object?>{
      for (final MapEntry<String, ReadingProgress> e in progress.entries)
        e.key: e.value.toJson(),
    },
    'vocabLists': vocabLists.toJson(),
  };

  factory ReadingLibrarySnapshot.fromStateJson(Map<String, dynamic> json) {
    final List<ReadingDoc> docs = <ReadingDoc>[];
    final Object? rawDocs = json['docs'];
    if (rawDocs is List) {
      for (final Object? item in rawDocs) {
        if (item is! Map) continue;
        final ReadingDoc doc = ReadingDoc.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (doc.id.isEmpty) continue;
        if (!doc.hasBody && (doc.contentHash == null || doc.contentHash!.isEmpty)) {
          continue;
        }
        docs.add(doc);
      }
    }
    final Map<String, ReadingProgress> progress = <String, ReadingProgress>{};
    final Object? rawProgress = json['progress'];
    if (rawProgress is Map) {
      for (final MapEntry<dynamic, dynamic> e in rawProgress.entries) {
        if (e.value is! Map) continue;
        final ReadingProgress p = ReadingProgress.fromJson(
          Map<String, dynamic>.from(e.value as Map),
        );
        if (p.docId.isNotEmpty) progress[p.docId] = p;
      }
    }
    final Object? rawLists = json['vocabLists'];
    final ReadingVocabLists lists = ReadingVocabLists.fromJson(
      rawLists is Map ? Map<String, dynamic>.from(rawLists) : null,
    );
    return ReadingLibrarySnapshot(
      docs: docs,
      progress: progress,
      vocabLists: lists,
    );
  }
}

ReadingLibrarySnapshot mergeReadingLibraries(
  ReadingLibrarySnapshot local,
  ReadingLibrarySnapshot remote,
) {
  final Map<String, ReadingDoc> docs = <String, ReadingDoc>{
    for (final ReadingDoc d in local.docs) d.id: d,
  };
  for (final ReadingDoc remoteDoc in remote.docs) {
    final ReadingDoc? localDoc = docs[remoteDoc.id];
    if (localDoc == null) {
      docs[remoteDoc.id] = remoteDoc;
      continue;
    }
    docs[remoteDoc.id] = _preferRicherDoc(localDoc, remoteDoc);
  }

  final Map<String, ReadingProgress> progress = <String, ReadingProgress>{
    ...local.progress,
  };
  for (final MapEntry<String, ReadingProgress> e in remote.progress.entries) {
    final ReadingProgress? localP = progress[e.key];
    if (localP == null) {
      progress[e.key] = e.value;
      continue;
    }
    progress[e.key] = _preferNewerProgress(localP, e.value);
  }

  return ReadingLibrarySnapshot(
    docs: docs.values.toList(growable: false),
    progress: progress,
    vocabLists: ReadingVocabLists(
      known: <String>{...local.vocabLists.known, ...remote.vocabLists.known},
      focus: <String>{...local.vocabLists.focus, ...remote.vocabLists.focus},
    ),
  );
}

ReadingDoc _preferRicherDoc(ReadingDoc a, ReadingDoc b) {
  ReadingDoc richer;
  if (a.hasBody && !b.hasBody) {
    richer = a;
  } else if (b.hasBody && !a.hasBody) {
    richer = b;
  } else if (a.plainText.length != b.plainText.length) {
    richer = a.plainText.length >= b.plainText.length ? a : b;
  } else {
    final DateTime? ac = a.createdAt;
    final DateTime? bc = b.createdAt;
    if (ac != null && bc != null) {
      richer = ac.isAfter(bc) ? a : b;
    } else {
      richer = a;
    }
  }
  final ReadingDoc other = identical(richer, a) ? b : a;
  // Cloud backups often omit coverUrl; never wipe a local jacket pointer.
  return richer.copyWith(
    coverUrl: richer.coverUrl.trim().isNotEmpty
        ? richer.coverUrl
        : other.coverUrl,
    titleZh: richer.titleZh.trim().isNotEmpty ? richer.titleZh : other.titleZh,
  );
}

ReadingProgress _preferNewerProgress(ReadingProgress a, ReadingProgress b) {
  final DateTime? al = a.lastOpenedAt;
  final DateTime? bl = b.lastOpenedAt;
  if (al != null && bl != null) {
    if (al.isAfter(bl)) return a;
    if (bl.isAfter(al)) return b;
  } else if (al != null) {
    return a;
  } else if (bl != null) {
    return b;
  }
  if (a.percent != b.percent) return a.percent >= b.percent ? a : b;
  return a.completed ? a : b;
}

/// Shrink largest plainText bodies until encoded size fits the API limit.
ReadingLibrarySnapshot shrinkReadingSnapshotForUpload(
  ReadingLibrarySnapshot snapshot,
) {
  List<ReadingDoc> docs = List<ReadingDoc>.from(snapshot.docs);
  Map<String, dynamic> state = ReadingLibrarySnapshot(
    docs: docs,
    progress: snapshot.progress,
    vocabLists: snapshot.vocabLists,
  ).toStateJson();
  String encoded = jsonEncode(state);
  if (utf8.encode(encoded).length <= kReadingBackupMaxBytes) {
    return snapshot;
  }

  while (utf8.encode(encoded).length > kReadingBackupMaxBytes) {
    int largestIndex = -1;
    int largestSize = 0;
    for (int i = 0; i < docs.length; i++) {
      final int size = docs[i].plainText.length;
      if (size > largestSize) {
        largestSize = size;
        largestIndex = i;
      }
    }
    if (largestIndex < 0 || largestSize == 0) break;
    final ReadingDoc doc = docs[largestIndex];
    final String hash =
        doc.contentHash ??
        sha256.convert(utf8.encode(doc.plainText)).toString();
    docs[largestIndex] = doc.copyWith(
      plainText: '',
      segments: const <ReadingSegment>[],
      contentHash: hash,
    );
    state = ReadingLibrarySnapshot(
      docs: docs,
      progress: snapshot.progress,
      vocabLists: snapshot.vocabLists,
    ).toStateJson();
    encoded = jsonEncode(state);
  }

  return ReadingLibrarySnapshot(
    docs: docs,
    progress: snapshot.progress,
    vocabLists: snapshot.vocabLists,
  );
}
