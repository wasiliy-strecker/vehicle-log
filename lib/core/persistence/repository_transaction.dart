typedef RepositoryTransaction =
    Future<void> Function(Future<void> Function() operation);

abstract interface class RepositoryTransactionRunner {
  Future<void> runTransaction(Future<void> Function() operation);
}

Future<void> runWithoutTransaction(Future<void> Function() operation) =>
    operation();
