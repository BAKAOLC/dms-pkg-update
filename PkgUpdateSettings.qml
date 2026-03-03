import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "pkgUpdate"

    StyledText {
        width: parent.width
        text: "Package Updates"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure how DNF and Flatpak updates are checked and applied."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "terminalApp"
        label: "Terminal Application"
        description: "Command used to open the terminal for running updates. Most terminals accept '-e' to run a command (e.g. 'alacritty', 'kitty', 'foot', 'ghostty')."
        defaultValue: "alacritty"
        placeholder: "alacritty"
    }

    SliderSetting {
        settingKey: "refreshMins"
        label: "Refresh Interval"
        description: "How often to check for available updates, in minutes."
        defaultValue: 60
        minimum: 5
        maximum: 240
        unit: "min"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "checkOnStartup"
        label: "Check on Startup"
        description: "Run an update check immediately when the shell starts, before the first periodic interval."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "maxListHeight"
        label: "Max List Height"
        description: "Maximum height of each update list area inside the popout before it becomes scrollable."
        defaultValue: 180
        minimum: 120
        maximum: 400
        unit: "px"
        leftIcon: "height"
    }

    ToggleSetting {
        settingKey: "showFlatpak"
        label: "Show Flatpak Updates"
        description: "Check and display Flatpak application updates alongside DNF packages."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "hideWhenNoUpdates"
        label: "Hide When Up-to-Date"
        description: "Hide this widget from the bar when no package updates are available."
        defaultValue: false
    }
}