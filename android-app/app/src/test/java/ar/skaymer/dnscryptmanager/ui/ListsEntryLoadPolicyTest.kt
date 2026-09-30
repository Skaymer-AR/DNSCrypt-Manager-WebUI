package ar.skaymer.dnscryptmanager.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ListsEntryLoadPolicyTest {
    @Test
    fun firstEntryLoadsDataThatIsNotCached() {
        assertEquals(
            ListsEntryLoadPlan(catalog = true, downloadProgress = true),
            listsEntryLoadPlan(catalogLoaded = false, downloadProgressLoaded = false),
        )
    }

    @Test
    fun returningToListsReusesTheLoadedData() {
        assertEquals(
            ListsEntryLoadPlan(catalog = false, downloadProgress = false),
            listsEntryLoadPlan(catalogLoaded = true, downloadProgressLoaded = true),
        )
    }

    @Test
    fun missingProgressDoesNotReloadAnAlreadyCachedCatalog() {
        assertEquals(
            ListsEntryLoadPlan(catalog = false, downloadProgress = true),
            listsEntryLoadPlan(catalogLoaded = true, downloadProgressLoaded = false),
        )
    }
}
