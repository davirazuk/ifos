import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    color: "#10241d"

    // SDDM passes the chosen session by index. This has to be a real property:
    // the previous version assigned to a bare `sessionIndex`, which is an error
    // in QML and left the login call referencing an undefined value.
    property int sessionIndex: sessionSelect.currentIndex

    function attemptLogin() {
        errorText.text = ""
        sddm.login(userField.text, passField.text, root.sessionIndex)
    }

    function updateClock() {
        var now = new Date()
        timeText.text = Qt.formatTime(now, "hh:mm")
        dateText.text = Qt.formatDate(now, "dddd, MMMM d")
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorText.text = "Incorrect username or password"
            passField.text = ""
            passField.forceActiveFocus()
        }
    }

    Image {
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    Rectangle {
        anchors.fill: parent
        color: "#10241d"
        opacity: 0.55
    }

    // ── Login card ───────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 360
        height: 390
        radius: 16
        color: "#10241d"
        border.color: "#1b3a2e"
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: parent.width - 60

            Text {
                text: "IFOS"
                font.pixelSize: 38
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
                color: "#00a86b"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Welcome back"
                font.pixelSize: 13
                color: "#7fa392"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            TextField {
                id: userField
                width: parent.width
                height: 42
                placeholderText: "Username"
                text: userModel.lastUser
                font.pixelSize: 13
                color: "#e8f5e9"
                leftPadding: 14
                background: Rectangle {
                    color: "#1b3a2e"
                    radius: 8
                    border.color: userField.activeFocus ? "#00a86b" : "#24503f"
                    border.width: 1
                }
                KeyNavigation.tab: passField
                Keys.onReturnPressed: passField.forceActiveFocus()
            }

            TextField {
                id: passField
                width: parent.width
                height: 42
                placeholderText: "Password"
                echoMode: TextInput.Password
                font.pixelSize: 13
                color: "#e8f5e9"
                leftPadding: 14
                background: Rectangle {
                    color: "#1b3a2e"
                    radius: 8
                    border.color: passField.activeFocus ? "#00a86b" : "#24503f"
                    border.width: 1
                }
                Keys.onReturnPressed: root.attemptLogin()
            }

            Text {
                id: errorText
                width: parent.width
                text: ""
                color: "#f38ba8"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                id: loginBtn
                width: parent.width
                height: 42
                radius: 8
                color: loginMouse.pressed ? "#00c47d" : "#00a86b"

                Text {
                    anchors.centerIn: parent
                    text: "Log in"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#10241d"
                }

                MouseArea {
                    id: loginMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.attemptLogin()
                }
            }
        }
    }

    // ── Clock ────────────────────────────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        spacing: 4

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 42
            font.bold: true
            font.family: "JetBrainsMono Nerd Font"
            color: "#e8f5e9"
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 14
            color: "#7fa392"
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateClock()
    }

    // ── Session picker ───────────────────────────────────────────────────────
    ComboBox {
        id: sessionSelect
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width: 160
        height: 32
        model: sessionModel
        textRole: "name"
        currentIndex: sessionModel.lastIndex
        font.pixelSize: 11

        background: Rectangle {
            color: "#1b3a2e"
            radius: 6
        }
        contentItem: Text {
            leftPadding: 10
            text: sessionSelect.displayText
            color: "#e8f5e9"
            font: sessionSelect.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    // ── Power ────────────────────────────────────────────────────────────────
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 16
        spacing: 8

        Rectangle {
            width: 36; height: 36; radius: 8
            color: shutMouse.pressed ? "#f38ba8" : "#1b3a2e"
            Text { anchors.centerIn: parent; text: "⏻"; color: "#f38ba8"; font.pixelSize: 16 }
            MouseArea {
                id: shutMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
            }
        }

        Rectangle {
            width: 36; height: 36; radius: 8
            color: rebootMouse.pressed ? "#f9e2af" : "#1b3a2e"
            Text { anchors.centerIn: parent; text: "⟳"; color: "#f9e2af"; font.pixelSize: 16 }
            MouseArea {
                id: rebootMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }
    }

    Component.onCompleted: {
        root.updateClock()
        if (userField.text === "")
            userField.forceActiveFocus()
        else
            passField.forceActiveFocus()
    }
}
