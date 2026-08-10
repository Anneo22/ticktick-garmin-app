using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;

// Direction contract (concept seed d39802f1).
// Route stops, not generic cards: the list is a single vertical spine whose stops are tasks.
// Isolated navigation: Today/Overdue/Projects own their own bounds at the foot of the screen
//   and can never overlap a stop, so a navigation tap can never touch a task.
// Deliberate two-step completion: only the selected stop's completion node arms, and only a
//   separate confirm action completes. A row tap selects; a retap of the selected row does nothing.
// One geometry: layout() is the only place that computes a rectangle. Drawing and hit testing
//   both read the stored bounds, so a touch target is always exactly what was painted.
class TaskListView extends Ui.View {
    const CORAL = 0xFD4E5A;
    const KLEIN = 0x5A5CF5;
    const SURFACE = 0x1A1A1A;
    const TEXT = 0xD4D4D4;
    const MUTED = 0x888888;
    const HAIRLINE = 0x666666;
    const VISIBLE = 3;

    var controller;
    var screenWidth;
    var screenHeight;
    var rowBounds;
    var nodeBounds;
    var navBounds;
    var actionBounds;
    var actionKind;
    var listTop;
    var rowHeight;
    var titleHeight;
    var bodyHeight;

    function initialize(taskController) {
        View.initialize();
        controller = taskController;
        screenWidth = 0;
        screenHeight = 0;
        rowBounds = [];
        nodeBounds = [];
        navBounds = [];
        actionBounds = null;
        actionKind = null;
        listTop = 0;
        rowHeight = 0;
        titleHeight = 0;
        bodyHeight = 0;
    }

    function onShow() {
        if (controller.isPaired() && !controller.mode.equals("account")) {
            controller.refresh();
        }
    }

    function modeTitle() {
        if (controller.mode.equals("overdue")) {
            return "Overdue";
        }
        if (controller.mode.equals("projects")) {
            return "Projects";
        }
        if (controller.mode.equals("project")) {
            return controller.projectName instanceof String ? controller.projectName : "Project";
        }
        if (controller.mode.equals("account")) {
            return "Account";
        }
        return "Today";
    }

    function isCompactSize(width, height) {
        return width <= 280 || height <= 280;
    }

    function color(compact, rich, fallback) {
        return compact ? fallback : rich;
    }

    function statusLabel() {
        var status = controller.status;
        if (status.equals("synced") || status.equals("paired") || status.equals("reconciled")) {
            return "Synced";
        }
        if (status.equals("cached") || status.equals("offline_cache")) {
            return "Offline cache";
        }
        if (status.equals("syncing") || status.equals("switching_view") || status.equals("loading_more") || status.equals("syncing_change") || status.equals("completing")) {
            return "Syncing";
        }
        if (status.equals("offline_queued") || (status.length() >= 14 && status.substring(0, 14).equals("offline_queue_"))) {
            return "Changes queued";
        }
        if (status.equals("unpaired")) {
            return "Not paired";
        }
        if (status.equals("pair_pending")) {
            return "Approval pending";
        }
        if (status.equals("pairing")) {
            return "Starting pairing";
        }
        if (status.equals("request_timeout")) {
            return "Phone timed out";
        }
        if (status.equals("phone_unavailable")) {
            return "Open Garmin Connect";
        }
        if (status.equals("service_unavailable")) {
            return "Setup unavailable";
        }
        if (status.equals("network_error")) {
            return "Connection failed";
        }
        if (status.equals("pair_expired")) {
            return "Pairing expired";
        }
        if (status.equals("unpairing")) {
            return "Disconnecting";
        }
        if (status.equals("confirm_complete") || status.equals("confirm_unpair")) {
            return "Confirm action";
        }
        return "Needs attention";
    }

    function statusColor(compact) {
        var status = controller.status;
        if (status.equals("synced") || status.equals("paired") || status.equals("reconciled") || status.equals("pair_pending")) {
            return color(compact, TEXT, Gfx.COLOR_WHITE);
        }
        if (status.equals("network_error") || status.equals("request_timeout") || status.equals("phone_unavailable") || status.equals("service_unavailable") || status.equals("pair_expired") || status.equals("authorization_expired") || status.equals("completion_uncertain") || status.equals("change_rejected") || status.equals("queue_full") || status.equals("unpair_failed")) {
            return color(compact, CORAL, Gfx.COLOR_WHITE);
        }
        if (status.equals("syncing") || status.equals("loading_more") || status.equals("syncing_change") || status.equals("completing") || status.equals("pairing") || status.equals("unpairing") || status.equals("offline_queued")) {
            return color(compact, TEXT, Gfx.COLOR_WHITE);
        }
        return color(compact, MUTED, Gfx.COLOR_LT_GRAY);
    }

    function fitText(dc, text, font, maxWidth) {
        if (!(text instanceof String)) {
            return "Untitled";
        }
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var end = text.length();
        while (end > 1 && dc.getTextWidthInPixels(text.substring(0, end) + "...", font) > maxWidth) {
            end -= 1;
        }
        return text.substring(0, end) + "...";
    }

    function dueLabel(task) {
        var due = task["dueDate"];
        if (!(due instanceof String) || due.length() < 10) {
            return null;
        }
        if (controller.mode.equals("today")) {
            if (task["isAllDay"] == true || due.length() < 16) {
                return "All day";
            }
            return due.substring(11, 16);
        }
        return "Due  " + due.substring(5, 10);
    }

    // The single geometry pass. Every rectangle the app draws or hit tests is created here.
    function layout(width, height, titleFontHeight, bodyFontHeight) {
        screenWidth = width;
        screenHeight = height;
        titleHeight = titleFontHeight;
        bodyHeight = bodyFontHeight;
        rowBounds = [];
        nodeBounds = [];
        navBounds = [];
        actionBounds = null;
        actionKind = null;
        listTop = 0;
        rowHeight = 0;
        var compact = isCompactSize(width, height);
        listTop = headerTop(height, compact) + titleHeight + bodyHeight + (compact ? 4 : 12);
        if (!controller.isPaired()) {
            setAction("pair", width, height - (compact ? 44 : 96), compact);
            return;
        }
        if (controller.confirmingCompletion) {
            setAction("confirm_completion", width, height - (compact ? 44 : 96), compact);
            return;
        }
        if (controller.mode.equals("account")) {
            var accountAction = controller.reconciliationRequired ? "reconcile" : (controller.confirmingUnpair ? "confirm_unpair" : "arm_unpair");
            setAction(accountAction, width, height - (compact ? 44 : 96), compact);
            return;
        }
        layoutRoute(width, height, compact);
        if (controller.activeItems().size() == 0 && !controller.busy) {
            var actionY = navBounds[0][1] - (compact ? 34 : 58);
            setAction("refresh", width, actionY, compact);
        }
    }

    function layoutRoute(width, height, compact) {
        var navHeight = compact ? bodyHeight + 4 : 58;
        // The navigation sits well clear of the bottom bezel, and inside a narrower band than the
        // rows, so a round screen never clips the outer labels.
        var navTop = height - navHeight - (compact ? 2 : height / 8);
        rowHeight = (navTop - listTop) / VISIBLE;
        if (rowHeight > 86) {
            rowHeight = 86;
        }
        if (rowHeight < 28) {
            rowHeight = 28;
        }
        var nodeSize = compact ? 0 : rowHeight - 8;
        if (nodeSize > 72) {
            nodeSize = 72;
        }
        if (!compact && nodeSize < 44) {
            nodeSize = 44;
        }
        var nodeCenter = width / 7;
        var left = compact ? 6 : nodeCenter + nodeSize / 2 + 8;
        var right = compact ? width - 6 : width - width / 9;
        var items = controller.activeItems();
        var start = controller.selected - 1;
        if (start > items.size() - VISIBLE) {
            start = items.size() - VISIBLE;
        }
        if (start < 0) {
            start = 0;
        }
        for (var row = 0; row < VISIBLE && start + row < items.size(); row += 1) {
            var index = start + row;
            var y = listTop + row * rowHeight;
            rowBounds.add([left, y, right - left, rowHeight, index]);
            if (!compact) {
                nodeBounds.add([nodeCenter - nodeSize / 2, y + rowHeight / 2 - nodeSize / 2, nodeSize, nodeSize, index]);
            }
        }
        var navLeft = compact ? 0 : width / 5;
        var names = compact ? ["cycle"] : ["today", "overdue", "projects"];
        var cellWidth = (width - navLeft * 2) / names.size();
        for (var cell = 0; cell < names.size(); cell += 1) {
            navBounds.add([navLeft + cell * cellWidth, navTop, cellWidth, navHeight, names[cell]]);
        }
    }

    function headerTop(height, compact) {
        return compact ? 8 : height / 12;
    }

    function actionButtonBounds(width, y, compact) {
        var buttonWidth = compact ? width - 28 : width * 3 / 5;
        if (buttonWidth > 280) {
            buttonWidth = 280;
        }
        var buttonHeight = compact ? 30 : 64;
        return [(width - buttonWidth) / 2, y, buttonWidth, buttonHeight];
    }

    function setAction(kind, width, y, compact) {
        actionKind = kind;
        actionBounds = actionButtonBounds(width, y, compact);
    }

    function contains(bounds, x, y) {
        return x >= bounds[0] && x <= bounds[0] + bounds[2] && y >= bounds[1] && y <= bounds[1] + bounds[3];
    }

    // Hit testing reads only the stored bounds; it never recomputes geometry.
    function handleTap(coordinates) {
        if (!(coordinates instanceof Array) || coordinates.size() < 2 || screenWidth <= 0 || screenHeight <= 0) {
            return false;
        }
        var x = coordinates[0];
        var y = coordinates[1];
        // Pairing is the only full-screen target, because it is non-destructive and idempotent.
        if (!controller.isPaired()) {
            if (!controller.busy) {
                controller.activate();
            }
            return true;
        }
        // Navigation is isolated and always disarms, so it can never sit on top of a task.
        for (var nav = 0; nav < navBounds.size(); nav += 1) {
            if (contains(navBounds[nav], x, y)) {
                if (navBounds[nav][4].equals("cycle")) {
                    controller.cycleMode();
                } else {
                    controller.setMode(navBounds[nav][4]);
                }
                return true;
            }
        }
        // The action kind is frozen with the rendered bounds. A stale visible button can therefore
        // never turn into a different action if an asynchronous response changes controller state.
        if (actionBounds != null) {
            if (contains(actionBounds, x, y)) {
                handleAction();
            }
            return true;
        }
        // The completion node is the only tap that can arm, and only on the already selected stop.
        for (var node = 0; node < nodeBounds.size(); node += 1) {
            if (contains(nodeBounds[node], x, y)) {
                return tapNode(nodeBounds[node][4]);
            }
        }
        // A row tap selects. Retapping the selected row changes nothing.
        for (var row = 0; row < rowBounds.size(); row += 1) {
            if (contains(rowBounds[row], x, y)) {
                controller.select(rowBounds[row][4]);
                return true;
            }
        }
        // Empty space is accepted and ignored. It can never arm or complete.
        return true;
    }

    function handleAction() {
        if (actionKind == null || controller.busy) {
            return;
        }
        if (actionKind.equals("pair")) {
            if (!controller.isPaired()) {
                controller.activate();
            }
            return;
        }
        if (actionKind.equals("refresh")) {
            if (controller.isPaired() && !controller.confirmingCompletion && !controller.mode.equals("account") && controller.activeItems().size() == 0) {
                controller.refresh();
            }
            return;
        }
        if (actionKind.equals("reconcile")) {
            if (controller.mode.equals("account") && controller.reconciliationRequired) {
                controller.activate();
            }
            return;
        }
        if (actionKind.equals("confirm_completion")) {
            if (controller.confirmingCompletion) {
                controller.activate();
            }
            return;
        }
        if (actionKind.equals("arm_unpair")) {
            if (controller.mode.equals("account") && !controller.confirmingUnpair) {
                controller.activate();
            }
            return;
        }
        if (actionKind.equals("confirm_unpair") && controller.mode.equals("account") && controller.confirmingUnpair) {
            controller.activate();
        }
    }

    function tapNode(index) {
        if (index != controller.selected) {
            controller.select(index);
            return true;
        }
        if (controller.mode.equals("projects")) {
            controller.activate();
            return true;
        }
        controller.armCompletion();
        return true;
    }

    function onUpdate(dc) {
        var compact = isCompactSize(dc.getWidth(), dc.getHeight());
        var titleFont = compact ? Gfx.FONT_XTINY : Gfx.FONT_SMALL;
        layout(dc.getWidth(), dc.getHeight(), dc.getFontHeight(titleFont), dc.getFontHeight(Gfx.FONT_XTINY));
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), color(compact, SURFACE, Gfx.COLOR_BLACK));
        dc.clear();

        drawHeader(dc, compact);
        if (!controller.isPaired()) {
            drawPairing(dc, compact);
            return;
        }
        if (controller.confirmingCompletion) {
            drawCompletionConfirm(dc, compact);
            return;
        }
        if (controller.mode.equals("account")) {
            drawAccount(dc, compact);
            return;
        }
        if (controller.activeItems().size() == 0) {
            if (controller.busy) {
                drawLoading(dc, compact);
            } else {
                drawEmpty(dc, compact);
            }
            if (compact) {
                drawCompactNavigation(dc);
            } else {
                drawNavigation(dc);
            }
            return;
        }
        if (compact) {
            drawCompactRows(dc);
            return;
        }
        drawRoute(dc);
        drawNavigation(dc);
    }

    function drawHeader(dc, compact) {
        var width = dc.getWidth();
        var top = headerTop(dc.getHeight(), compact);
        var titleFont = compact ? Gfx.FONT_XTINY : Gfx.FONT_SMALL;
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, top, titleFont, fitText(dc, modeTitle(), titleFont, width - (compact ? 46 : width / 4)), Gfx.TEXT_JUSTIFY_CENTER);

        var statusY = top + titleHeight + (compact ? 1 : 2);
        var fitted = fitText(dc, statusLabel(), Gfx.FONT_XTINY, width - (compact ? 24 : width / 4));
        dc.setColor(statusColor(compact), Gfx.COLOR_TRANSPARENT);
        if (!compact) {
            dc.setColor(KLEIN, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(width / 2 - dc.getTextWidthInPixels(fitted, Gfx.FONT_XTINY) / 2 - 7, statusY + bodyHeight / 2, 3);
            dc.setColor(statusColor(compact), Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(width / 2 + (compact ? 0 : 5), statusY, Gfx.FONT_XTINY, fitted, Gfx.TEXT_JUSTIFY_CENTER);
        var itemCount = controller.activeItems().size();
        if (!compact && itemCount > VISIBLE) {
            dc.setColor(MUTED, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width - width / 7, statusY, Gfx.FONT_XTINY, (controller.selected + 1).format("%d") + "/" + itemCount.format("%d"), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    // A route, not a stack of cards: one spine, one stop per task, the selected stop lit.
    function drawRoute(dc) {
        var items = controller.activeItems();
        var isProjects = controller.mode.equals("projects");
        var spineX = nodeBounds[0][0] + nodeBounds[0][2] / 2;
        var firstY = nodeBounds[0][1] + nodeBounds[0][3] / 2;
        var lastNode = nodeBounds[nodeBounds.size() - 1];
        dc.setColor(HAIRLINE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(spineX, firstY, spineX, lastNode[1] + lastNode[3] / 2);

        for (var row = 0; row < rowBounds.size(); row += 1) {
            var bounds = rowBounds[row];
            var index = bounds[4];
            var item = items[index];
            var selected = index == controller.selected;
            var node = nodeBounds[row];
            var centerY = node[1] + node[3] / 2;

            if (selected && row > 0) {
                dc.setColor(CORAL, Gfx.COLOR_TRANSPARENT);
                dc.drawLine(spineX, rowBounds[row - 1][1] + rowBounds[row - 1][3] / 2, spineX, centerY);
            }
            if (row + 1 < rowBounds.size()) {
                dc.setColor(HAIRLINE, Gfx.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawLine(bounds[0], bounds[1] + bounds[3], bounds[0] + bounds[2], bounds[1] + bounds[3]);
                dc.setPenWidth(2);
            }

            dc.setColor(SURFACE, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(spineX, centerY, node[2] / 2 - 4);
            dc.setColor(selected ? CORAL : MUTED, Gfx.COLOR_TRANSPARENT);
            if (isProjects) {
                dc.drawText(spineX, centerY - bodyHeight / 2, Gfx.FONT_XTINY, ">", Gfx.TEXT_JUSTIFY_CENTER);
            } else {
                dc.drawCircle(spineX, centerY, node[2] / 2 - 7);
                if (selected) {
                    dc.fillCircle(spineX, centerY, 5);
                }
            }

            var label = isProjects ? item["name"] : item["title"];
            var due = isProjects ? null : dueLabel(item);
            var textX = bounds[0];
            var textWidth = bounds[2];
            var textY = due == null ? centerY - bodyHeight / 2 : bounds[1] + (bounds[3] - bodyHeight * 2) / 2;
            dc.setColor(selected ? TEXT : MUTED, Gfx.COLOR_TRANSPARENT);
            dc.drawText(textX, textY, Gfx.FONT_XTINY, fitText(dc, label, Gfx.FONT_XTINY, textWidth), Gfx.TEXT_JUSTIFY_LEFT);
            if (due != null) {
                dc.setColor(MUTED, Gfx.COLOR_TRANSPARENT);
                dc.drawText(textX, textY + bodyHeight, Gfx.FONT_XTINY, due, Gfx.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.setPenWidth(1);
    }

    function navLabel(name) {
        if (name.equals("overdue")) {
            return "Late";
        }
        return name.equals("projects") ? "Lists" : "Today";
    }

    function navActive(name) {
        if (name.equals("projects")) {
            return controller.mode.equals("projects") || controller.mode.equals("project");
        }
        return controller.mode.equals(name);
    }

    function drawNavigation(dc) {
        for (var cell = 0; cell < navBounds.size(); cell += 1) {
            var bounds = navBounds[cell];
            var name = bounds[4];
            var active = navActive(name);
            var centerX = bounds[0] + bounds[2] / 2;
            if (active) {
                dc.setColor(KLEIN, Gfx.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawLine(centerX - 16, bounds[1] + bounds[3] - 7, centerX + 16, bounds[1] + bounds[3] - 7);
                dc.setPenWidth(1);
            }
            dc.setColor(active ? TEXT : MUTED, Gfx.COLOR_TRANSPARENT);
            dc.drawText(centerX, bounds[1] + bounds[3] - bodyHeight - 2, Gfx.FONT_XTINY, navLabel(name), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawCompactRows(dc) {
        var items = controller.activeItems();
        for (var row = 0; row < rowBounds.size(); row += 1) {
            var bounds = rowBounds[row];
            var index = bounds[4];
            var item = items[index];
            var label = controller.mode.equals("projects") ? item["name"] : item["title"];
            dc.setColor(index == controller.selected ? Gfx.COLOR_WHITE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(bounds[0], bounds[1], Gfx.FONT_XTINY, (index == controller.selected ? "> " : "  ") + fitText(dc, label, Gfx.FONT_XTINY, bounds[2] - 12), Gfx.TEXT_JUSTIFY_LEFT);
        }
        drawCompactNavigation(dc);
    }

    function drawCompactNavigation(dc) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        var footer = navBounds[0];
        var label = "MENU views";
        var itemCount = controller.activeItems().size();
        if (itemCount > VISIBLE) {
            label += "  " + (controller.selected + 1).format("%d") + "/" + itemCount.format("%d");
        }
        dc.drawText(dc.getWidth() / 2, footer[1] + footer[3] - bodyHeight, Gfx.FONT_XTINY, fitText(dc, label, Gfx.FONT_XTINY, dc.getWidth() - 12), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawActionButton(dc, compact, label) {
        dc.setColor(color(compact, CORAL, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(actionBounds[0], actionBounds[1], actionBounds[2], actionBounds[3], compact ? 7 : 12);
        dc.setColor(color(compact, SURFACE, Gfx.COLOR_BLACK), Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            actionBounds[1] + (actionBounds[3] - bodyHeight) / 2,
            Gfx.FONT_XTINY,
            fitText(dc, label, Gfx.FONT_XTINY, actionBounds[2] - 18),
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function drawCenteredBlock(dc, compact, lines) {
        var width = dc.getWidth();
        var top = listTop + (actionBounds[1] - listTop - lines.size() * bodyHeight) / 2;
        for (var line = 0; line < lines.size(); line += 1) {
            dc.drawText(width / 2, top + line * bodyHeight, Gfx.FONT_XTINY, fitText(dc, lines[line], Gfx.FONT_XTINY, width - (compact ? 20 : width / 4)), Gfx.TEXT_JUSTIFY_CENTER);
        }
        return top;
    }

    // The single route stop shown above a decision, so a confirmation still reads as the same object.
    function drawStopMark(dc, compact, top, filled) {
        if (compact) {
            return;
        }
        dc.setColor(filled ? CORAL : MUTED, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(dc.getWidth() / 2, top - 22, 9);
        if (filled) {
            dc.fillCircle(dc.getWidth() / 2, top - 22, 4);
        }
    }

    function drawEmpty(dc, compact) {
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        var top = drawCenteredBlock(dc, compact, [controller.mode.equals("projects") ? "No projects" : "All clear"]);
        drawStopMark(dc, compact, top, false);
        drawActionButton(dc, compact, "REFRESH");
    }

    function drawLoading(dc, compact) {
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        var bottom = compact ? screenHeight : navBounds[0][1];
        var top = listTop + (bottom - listTop - bodyHeight) / 2;
        dc.drawText(screenWidth / 2, top, Gfx.FONT_XTINY, "Loading...", Gfx.TEXT_JUSTIFY_CENTER);
        if (!compact) {
            drawStopMark(dc, compact, top, false);
        }
    }

    function drawCompletionConfirm(dc, compact) {
        var task = controller.completionTask();
        if (task == null) {
            return;
        }
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        var top = drawCenteredBlock(dc, compact, ["Complete task?", task["title"]]);
        drawStopMark(dc, compact, top, true);
        drawActionButton(dc, compact, "CONFIRM");
    }

    function drawAccount(dc, compact) {
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        if (controller.reconciliationRequired) {
            drawCenteredBlock(dc, compact, ["Check latest change", "Sync before continuing"]);
            drawActionButton(dc, compact, "SYNC NOW");
            return;
        }
        var lines = [
            controller.confirmingUnpair ? "Disconnect?" : "Disconnect TickTick",
            controller.confirmingUnpair ? "Removes this watch only" : "Keep cached tasks until confirmed"
        ];
        if (controller.confirmingUnpair && controller.queue.size() > 0) {
            lines.add(controller.queue.size().format("%d") + " queued change(s) will be lost");
        }
        drawCenteredBlock(dc, compact, lines);
        drawActionButton(dc, compact, controller.confirmingUnpair ? "CONFIRM" : "DISCONNECT");
    }

    function drawPairing(dc, compact) {
        var code = controller.store.getUserCode();
        var lines = ["Pair TickTick", "One-time phone setup"];
        if (code != null) {
            lines = compact ? ["Approve pairing", "Approve on your phone", code] : ["Approve pairing", "Approve on your phone"];
        }
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        var top = drawCenteredBlock(dc, compact, lines);
        if (code != null && !compact) {
            dc.drawText(dc.getWidth() / 2, top + lines.size() * bodyHeight + 6, Gfx.FONT_MEDIUM, code, Gfx.TEXT_JUSTIFY_CENTER);
        }
        drawStopMark(dc, compact, top, code != null);
        drawActionButton(dc, compact, pairActionLabel(code));
    }

    function pairActionLabel(code) {
        if (controller.busy) {
            return code == null ? "CONNECTING" : "CHECKING";
        }
        if (code != null) {
            return "CHECK STATUS";
        }
        var status = controller.status;
        if (status.equals("network_error") || status.equals("request_timeout") || status.equals("phone_unavailable") || status.equals("service_unavailable") || status.equals("pair_expired")) {
            return "TRY AGAIN";
        }
        return "START PAIRING";
    }
}
