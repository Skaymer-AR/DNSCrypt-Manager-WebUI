package ar.skaymer.dnscryptmanager.ui

import ar.skaymer.dnscryptmanager.ActivityEvent

/**
 * Activity timestamps only have second precision, so two identical queries can
 * share time/domain/status. Include the position to keep lazy-list keys unique.
 */
internal fun activityLazyItemKey(index: Int, event: ActivityEvent): String =
    "$index:${event.time}:${event.domain}:${event.status}"
