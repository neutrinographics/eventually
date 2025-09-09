import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:eventually/eventually.dart';

void main() {
  group('CID', () {
    test('creates v1 CID with SHA-256', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.sha256, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);

      expect(cid.version, equals(1));
      expect(cid.codec, equals(MultiCodec.raw));
      expect(cid.multihash.code, equals(MultiHashCode.sha256));
    });

    test('creates v0 CID with SHA-256', () {
      final data = Uint8List(32); // 32-byte hash
      final hash = Multihash.fromDigest(MultiHashCode.sha256, data);
      final cid = CID.v0(hash);

      expect(cid.version, equals(0));
      expect(cid.codec, equals(MultiCodec.dagPb));
      expect(cid.multihash.code, equals(MultiHashCode.sha256));
    });

    test('equality works correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash1 = Multihash.fromDigest(MultiHashCode.sha256, data);
      final hash2 = Multihash.fromDigest(MultiHashCode.sha256, data);

      final cid1 = CID.v1(codec: MultiCodec.raw, multihash: hash1);
      final cid2 = CID.v1(codec: MultiCodec.raw, multihash: hash2);

      expect(cid1, equals(cid2));
      expect(cid1.hashCode, equals(cid2.hashCode));
    });
  });

  group('Block', () {
    test('creates block from data', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final block = Block.fromData(data, codec: MultiCodec.raw);

      expect(block.size, equals(5));
      expect(block.data, equals(data));
      expect(block.cid.codec, equals(MultiCodec.raw));
    });

    test('validates block integrity', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      // Identity hash should work for validation
      expect(block.size, equals(5));
      expect(block.isEmpty, isFalse);
      expect(block.isNotEmpty, isTrue);
    });

    test('extracts links from blocks', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      // Raw blocks should have no links
      final links = block.extractLinks();
      expect(links, isEmpty);
    });
  });

  group('DAG', () {
    test('adds and retrieves blocks', () {
      final dag = DAG();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      dag.addBlock(block);

      expect(dag.hasBlock(cid), isTrue);
      expect(dag.getBlock(cid), equals(block));
      expect(dag.size, equals(1));
      expect(dag.isEmpty, isFalse);
    });

    test('removes blocks', () {
      final dag = DAG();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      dag.addBlock(block);
      expect(dag.hasBlock(cid), isTrue);

      final removed = dag.removeBlock(cid);
      expect(removed, isTrue);
      expect(dag.hasBlock(cid), isFalse);
      expect(dag.size, equals(0));
    });

    test('calculates statistics', () {
      final dag = DAG();
      final stats = dag.calculateStats();

      expect(stats.totalBlocks, equals(0));
      expect(stats.totalSize, equals(0));
      expect(stats.rootBlocks, equals(0));
      expect(stats.leafBlocks, equals(0));
    });
  });

  group('MemoryStore', () {
    test('stores and retrieves blocks', () async {
      final store = MemoryStore();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      final stored = await store.put(block);
      expect(stored, isTrue);

      final retrieved = await store.get(cid);
      expect(retrieved, equals(block));

      final exists = await store.has(cid);
      expect(exists, isTrue);
    });

    test('handles multiple blocks', () async {
      final store = MemoryStore();
      final blocks = <Block>[];

      for (int i = 0; i < 3; i++) {
        final data = Uint8List.fromList([i, i + 1, i + 2]);
        final hash = Multihash.fromDigest(MultiHashCode.identity, data);
        final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
        final block = Block.withCid(cid, data);
        blocks.add(block);
      }

      final results = await store.putAll(blocks);
      expect(results.length, equals(3));
      expect(results.values.every((success) => success), isTrue);

      final cids = blocks.map((b) => b.cid).toList();
      final retrieved = await store.getAll(cids);
      expect(retrieved.length, equals(3));
    });

    test('gets statistics', () async {
      final store = MemoryStore();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      await store.put(block);

      final stats = await store.getStats();
      expect(stats.totalBlocks, equals(1));
      expect(stats.totalSize, equals(5));
      expect(stats.averageBlockSize, equals(5.0));
    });
  });

  group('Multihash', () {
    test('creates from digest', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);

      expect(hash.code, equals(MultiHashCode.identity));
      expect(hash.size, equals(5));
      expect(hash.digest, equals(data));
    });

    test('round-trip encoding', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash1 = Multihash.fromDigest(MultiHashCode.identity, data);
      final bytes = hash1.bytes;
      final hash2 = Multihash.fromBytes(bytes);

      expect(hash1, equals(hash2));
    });
  });

  group('Peer', () {
    test('creates peer with metadata', () {
      final peer = Peer(
        id: 'peer-123',
        address: '127.0.0.1:8080',
        metadata: {'version': '1.0.0'},
      );

      expect(peer.id, equals('peer-123'));
      expect(peer.address, equals('127.0.0.1:8080'));
      expect(peer.metadata['version'], equals('1.0.0'));
    });

    test('equality and hashing work correctly', () {
      final peer1 = Peer(id: 'peer-123', address: '127.0.0.1:8080');
      final peer2 = Peer(id: 'peer-123', address: '127.0.0.1:8080');
      final peer3 = Peer(id: 'peer-456', address: '127.0.0.1:8080');

      expect(peer1, equals(peer2));
      expect(peer1.hashCode, equals(peer2.hashCode));
      expect(peer1, isNot(equals(peer3)));
    });
  });

  group('Protocol Messages', () {
    test('creates block request', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);

      final request = BlockRequest(cid: cid);
      expect(request.type, equals('block_request'));
      expect(request.cid, equals(cid));

      // Should be able to convert to bytes
      final bytes = request.toBytes();
      expect(bytes, isNotEmpty);
    });

    test('creates block response', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final block = Block.withCid(cid, data);

      final response = BlockResponse(block: block);
      expect(response.type, equals('block_response'));
      expect(response.block, equals(block));
    });

    test('creates have and want messages', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final hash = Multihash.fromDigest(MultiHashCode.identity, data);
      final cid = CID.v1(codec: MultiCodec.raw, multihash: hash);
      final cids = {cid};

      final have = Have(cids: cids);
      expect(have.type, equals('have'));
      expect(have.cids, equals(cids));

      final want = Want(cids: cids);
      expect(want.type, equals('want'));
      expect(want.cids, equals(cids));
    });

    test('creates ping and pong messages', () {
      final ping = Ping();
      expect(ping.type, equals('ping'));

      final pong = Pong();
      expect(pong.type, equals('pong'));
    });
  });

  group('Codecs', () {
    test('raw codec encodes and decodes', () {
      final codec = RawCodec();
      final data = [1, 2, 3, 4, 5];

      expect(codec.code, equals(CodecType.raw));
      expect(codec.name, equals('raw'));
      expect(codec.canEncode(data), isTrue);

      final encoded = codec.encode(data);
      expect(encoded, equals(data));

      final decoded = codec.decode(encoded);
      expect(decoded, equals(data));
    });

    test('codec factory creates codecs', () {
      expect(CodecFactory.isSupported(CodecType.raw), isTrue);
      expect(CodecFactory.isSupported(CodecType.dagPb), isTrue);
      expect(CodecFactory.isSupported(999), isFalse);

      final rawCodec = CodecFactory.create(CodecType.raw);
      expect(rawCodec, isA<RawCodec>());
    });
  });

  group('Hash Factory', () {
    test('creates identity hasher', () {
      final hasher = HashFactory.create(HashCode.identity);
      expect(hasher.code, equals(HashCode.identity));
      expect(hasher.name, equals('identity'));

      final data = Uint8List.fromList([1, 2, 3]);
      final hash = hasher.hash(data);
      expect(hash, equals(data));
    });

    test('checks supported hash codes', () {
      expect(HashFactory.isSupported(HashCode.identity), isTrue);
      expect(HashFactory.isSupported(HashCode.sha256), isTrue);
      expect(HashFactory.isSupported(999), isFalse);
    });
  });

  group('Directory Block', () {
    test('creates directory with entries', () {
      final fileData = Uint8List.fromList([1, 2, 3]);
      final fileHash = Multihash.fromDigest(MultiHashCode.identity, fileData);
      final fileCid = CID.v1(codec: MultiCodec.raw, multihash: fileHash);

      final entries = {
        'file1.txt': DirectoryEntry.file(fileCid, fileData.length),
        'subdir': DirectoryEntry.directory(fileCid, 100),
      };

      final dirBlock = DirectoryBlock(entries);
      expect(dirBlock.length, equals(2));
      expect(dirBlock.contains('file1.txt'), isTrue);
      expect(dirBlock['file1.txt']?.type, equals(EntryType.file));
      expect(dirBlock['subdir']?.type, equals(EntryType.directory));
    });
  });
}
