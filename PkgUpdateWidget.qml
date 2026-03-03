import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    function clampInt(value, min, max, fallbackValue) {
        const parsed = Number(value)
        if (!isFinite(parsed))
            return fallbackValue
        return Math.max(min, Math.min(max, Math.round(parsed)))
    }

    // ── Source model ──────────────────────────────────────────────────────────
    readonly property var sourceOrder: ["dnf", "flatpak"]
    readonly property var sourceDefinitions: ({
            "dnf": {
                id: "dnf",
                label: "DNF",
                checkCommand: "dnf list --upgrades --color=never 2>/dev/null",
                updateCommand: "sudo dnf upgrade -y"
            },
            "flatpak": {
                id: "flatpak",
                label: "Flatpak",
                checkCommand: "flatpak remote-ls --updates 2>/dev/null",
                updateCommand: "flatpak update -y"
            }
        })

    property var sourceUpdates: ({
            "dnf": [],
            "flatpak": []
        })

    property var sourceChecking: ({
            "dnf": true,
            "flatpak": true
        })

    // ── Settings (from plugin data) ───────────────────────────────────────────
    property string terminalApp: (pluginData.terminalApp && pluginData.terminalApp.trim().length > 0) ? pluginData.terminalApp.trim() : "alacritty"
    property int refreshMins: clampInt(pluginData.refreshMins, 5, 240, 60)
    property bool checkOnStartup: pluginData.checkOnStartup !== undefined ? pluginData.checkOnStartup : true
    property int maxListHeight: clampInt(pluginData.maxListHeight, 120, 400, 180)
    property bool showFlatpak: pluginData.showFlatpak !== undefined ? pluginData.showFlatpak : true
    property bool hideWhenNoUpdates: pluginData.hideWhenNoUpdates !== undefined ? pluginData.hideWhenNoUpdates : false

    readonly property int totalUpdates: totalUpdateCount()
    readonly property bool anyChecking: hasAnyCheckingSource()
    readonly property bool shouldHide: hideWhenNoUpdates && !anyChecking && totalUpdates === 0
    readonly property string summaryText: totalUpdates > 0 ? totalUpdates + " update" + (totalUpdates !== 1 ? "s" : "") + " available" : "System is up to date"

    visible: !shouldHide
    popoutWidth: 480

    // ── Periodic refresh ──────────────────────────────────────────────────────
    Timer {
        interval: root.refreshMins * 60000
        running: true
        repeat: true
        triggeredOnStart: root.checkOnStartup
        onTriggered: root.checkUpdates()
    }

    // ── Update check functions ────────────────────────────────────────────────
    function isSourceEnabled(sourceId) {
        if (sourceId === "flatpak")
            return root.showFlatpak
        return true
    }

    function sourceUpdatesFor(sourceId) {
        return sourceUpdates[sourceId] || []
    }

    function sourceCount(sourceId) {
        return sourceUpdatesFor(sourceId).length
    }

    function totalUpdateCount() {
        let total = 0
        for (const sourceId of sourceOrder) {
            if (isSourceEnabled(sourceId))
                total += sourceCount(sourceId)
        }
        return total
    }

    function sourceHasUpdates(sourceId) {
        return sourceCount(sourceId) > 0
    }

    function sourceIsChecking(sourceId) {
        return isSourceEnabled(sourceId) && !!sourceChecking[sourceId]
    }

    function hasAnyCheckingSource() {
        for (const sourceId of sourceOrder) {
            if (sourceIsChecking(sourceId))
                return true
        }
        return false
    }

    function withSourceValue(currentMap, sourceId, value) {
        const nextMap = ({})
        for (const key in currentMap)
            nextMap[key] = currentMap[key]
        nextMap[sourceId] = value
        return nextMap
    }

    function setSourceUpdates(sourceId, updates) {
        sourceUpdates = withSourceValue(sourceUpdates, sourceId, updates)
    }

    function setSourceChecking(sourceId, checking) {
        sourceChecking = withSourceValue(sourceChecking, sourceId, checking)
    }

    function parseUpdatesForSource(sourceId, stdout) {
        if (sourceId === "dnf")
            return parseDnfPackages(stdout)
        if (sourceId === "flatpak")
            return parseFlatpakApps(stdout)
        return []
    }

    function checkSourceUpdates(sourceId) {
        if (!isSourceEnabled(sourceId)) {
            setSourceChecking(sourceId, false)
            return
        }

        const definition = sourceDefinitions[sourceId]
        if (!definition) {
            setSourceChecking(sourceId, false)
            return
        }

        setSourceChecking(sourceId, true)
        Proc.runCommand("pkgUpdate." + sourceId, ["sh", "-c", definition.checkCommand], (stdout, exitCode) => {
            setSourceUpdates(sourceId, parseUpdatesForSource(sourceId, stdout))
            setSourceChecking(sourceId, false)
        }, 100)
    }

    function checkUpdates() {
        for (const sourceId of sourceOrder)
            checkSourceUpdates(sourceId)
    }

    function parseDnfPackages(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith('Last') && !t.startsWith('Upgradable') && !t.startsWith('Available') && !t.startsWith('Extra')
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            return {
                name: parts[0] || '',
                version: parts[1] || '',
                repo: parts[2] || ''
            }
        }).filter(p => p.name.length > 0 && p.name.indexOf('.') > -1)
    }

    function parseFlatpakApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => line.trim().length > 0).map(line => {
            const parts = line.trim().split(/\t|\s{2,}/)
            return {
                name: parts[0] || '',
                branch: parts[1] || '',
                origin: parts[2] || ''
            }
        }).filter(a => a.name.length > 0)
    }

    // ── Terminal launch ───────────────────────────────────────────────────────
    function runUpdateCommand(updateCommand) {
        root.closePopout()
        const cmd = updateCommand + "; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"])
    }

    function runSourceUpdate(sourceId) {
        const definition = sourceDefinitions[sourceId]
        if (!definition)
            return
        runUpdateCommand(definition.updateCommand)
    }

    function sectionHeight(isChecking, updatesCount) {
        if (isChecking)
            return 52
        if (updatesCount === 0)
            return 46
        return Math.min(updatesCount * 38 + 8, root.maxListHeight)
    }

    // ── Bar pills ─────────────────────────────────────────────────────────────
    horizontalBarPill: !root.shouldHide ? horizontalPillComponent : null
    verticalBarPill: !root.shouldHide ? verticalPillComponent : null

    Component {
        id: horizontalPillComponent

        Item {
            implicitWidth: root.shouldHide ? 0 : contentRow.implicitWidth
            implicitHeight: root.shouldHide ? 0 : contentRow.implicitHeight
            visible: !root.shouldHide

            Row {
                id: contentRow
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    size: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.anyChecking ? "…" : root.totalUpdates.toString()
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
        }
    }

    Component {
        id: verticalPillComponent

        Item {
            implicitWidth: root.shouldHide ? 0 : contentColumn.implicitWidth
            implicitHeight: root.shouldHide ? 0 : contentColumn.implicitHeight
            visible: !root.shouldHide

            Column {
                id: contentColumn
                spacing: 2
                anchors.horizontalCenter: parent.horizontalCenter

                DankIcon {
                    name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    size: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.anyChecking ? "…" : root.totalUpdates.toString()
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    // ── Popout ────────────────────────────────────────────────────────────────
    popoutContent: Component {
        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Header card
            Item {
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }

                        DankIcon {
                            name: "system_update"
                            size: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            text: "Package Updates"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.summaryText
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                        }
                    }
                }

                // Refresh button
                Item {
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : "transparent"
                    }

                    DankIcon {
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.checkUpdates()
                    }
                }
            }

            // ── DNF section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "archive"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "DNF"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: dnfCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: dnfCountLabel
                            text: root.sourceIsChecking("dnf") ? "…" : root.sourceCount("dnf").toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update DNF button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: dnfBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.sourceIsChecking("dnf") && root.sourceHasUpdates("dnf")

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: dnfBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    }

                    Row {
                        id: dnfBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: dnfBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update DNF"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: dnfBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: dnfBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runSourceUpdate("dnf")
                    }
                }
            }

            // ── DNF update list ──────────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.sectionHeight(root.sourceIsChecking("dnf"), root.sourceCount("dnf"))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.sourceIsChecking("dnf")

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.sourceIsChecking("dnf") && !root.sourceHasUpdates("dnf")

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.sourceUpdatesFor("dnf")
                    spacing: 2
                    visible: !root.sourceIsChecking("dnf") && root.sourceHasUpdates("dnf")

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string pkgName: modelData.name
                        property string pkgVersion: modelData.version

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "upgrade"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pkgName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - pkgVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: pkgVersionText
                                text: pkgVersion
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── Flatpak section header ────────────────────────────────────────
            Item {
                width: parent.width
                height: 36
                visible: root.isSourceEnabled("flatpak")

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "apps"
                        size: 20
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Flatpak"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: flatpakCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: flatpakCountLabel
                            text: root.sourceIsChecking("flatpak") ? "…" : root.sourceCount("flatpak").toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.secondary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Flatpak button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: flatpakBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.sourceIsChecking("flatpak") && root.sourceHasUpdates("flatpak")

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: flatpakBtnArea.containsMouse ? Theme.secondary : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
                    }

                    Row {
                        id: flatpakBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Flatpak"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: flatpakBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runSourceUpdate("flatpak")
                    }
                }
            }

            // ── Flatpak update list ──────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.sectionHeight(root.sourceIsChecking("flatpak"), root.sourceCount("flatpak"))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                clip: true
                visible: root.isSourceEnabled("flatpak")

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.sourceIsChecking("flatpak")

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.sourceIsChecking("flatpak") && !root.sourceHasUpdates("flatpak")

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.sourceUpdatesFor("flatpak")
                    spacing: 2
                    visible: !root.sourceIsChecking("flatpak") && root.sourceHasUpdates("flatpak")

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string appId: modelData.name
                        property string appOrigin: modelData.origin

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "extension"
                                size: 14
                                color: Theme.secondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: appId
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - appOriginText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: appOriginText
                                text: appOrigin
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}