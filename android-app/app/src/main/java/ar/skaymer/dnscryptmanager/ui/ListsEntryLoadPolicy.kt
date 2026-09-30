package ar.skaymer.dnscryptmanager.ui

internal data class ListsEntryLoadPlan(
    val catalog: Boolean,
    val downloadProgress: Boolean,
)

internal fun listsEntryLoadPlan(
    catalogLoaded: Boolean,
    downloadProgressLoaded: Boolean,
): ListsEntryLoadPlan = ListsEntryLoadPlan(
    catalog = !catalogLoaded,
    downloadProgress = !downloadProgressLoaded,
)
