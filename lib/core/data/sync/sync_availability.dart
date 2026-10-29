/// Whether a `RemoteSyncBackend` is wired into the provider graph, so that a
/// record's `syncStatus` can ever leave `pending`.
///
/// While it is false the app shows no sync status anywhere (SPEC 0235): every
/// record would read "Pendente" forever. The spec that wires `SyncEngine` to a
/// backend sets it to true, and Início, Histórico and Perfil show it again.
const syncBackendWired = false;
