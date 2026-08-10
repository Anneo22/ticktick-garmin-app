using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;

// Direction contract (concept seed d39802f1).
// Route stops, not generic cards: the list is a single vertical spine whose stops are tasks.
// Isolated navigation: Today/Inbox/Lists own their own bounds at the foot of the screen
//   and can never overlap a stop, so a navigation tap can never touch a task.
// Deliberate two-step completion: only the selected stop's completion node arms, and only a
//   separate confirm action completes. A row tap selects; a retap of the selected row does nothing.
// One geometry: layout() is the only place that computes a rectangle. Drawing and hit testing
//   both read the stored bounds, so a touch target is always exactly what was painted.
class TaskListView extends Ui.View {
    const CORAL = 0xFD4E5A;
    const KLEIN = 0x5A5CF5;
    const SURFACE = 0x1A1A1A;
    const REFERENCE_SURFACE = 0x080808;
    const TEXT = 0xD4D4D4;
    const MUTED = 0xA0A0A0;
    const HAIRLINE = 0x333333;
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
    var taskHeight;
    var visibleRows;
    var titleFont;
    var taskFont;
    var metaFont;
    var statusFont;
    var navFont;

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
        taskHeight = 0;
        visibleRows = VISIBLE;
        titleFont = Gfx.FONT_SMALL;
        taskFont = Gfx.FONT_XTINY;
        metaFont = Gfx.FONT_XTINY;
        statusFont = Gfx.FONT_XTINY;
        navFont = Gfx.FONT_XTINY;
    }

    function onShow() {
        if (controller.isPaired() && !controller.mode.equals("account")) {
            controller.refresh();
        }
    }

    function modeTitle() {
        if (controller.mode.equals("inbox")) {
            return "Inbox";
        }
        if (controller.mode.equals("overdue")) {
            return "Overdue";
        }
        if (controller.mode.equals("lists")) {
            return "Lists";
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

    function isReferenceSize(width, height) {
        return width >= 440 && height >= 440;
    }

    // The built-in Fenix fonts jump from too small to too large for the approved composition.
    // Current AMOLED devices expose Garmin's vector Roboto face, which lets the reference layout
    // use the intended scale without shipping a duplicate font. Every other watch keeps its
    // existing built-in fonts.
    function prepareFonts(width, height) {
        titleFont = isCompactSize(width, height) ? Gfx.FONT_XTINY : Gfx.FONT_SMALL;
        taskFont = Gfx.FONT_XTINY;
        metaFont = Gfx.FONT_XTINY;
        statusFont = Gfx.FONT_XTINY;
        navFont = Gfx.FONT_XTINY;
        if (!isReferenceSize(width, height) || !(Gfx has :getVectorFont)) {
            return;
        }
        var candidate = Gfx.getVectorFont({:face => "RobotoRegular", :size => 34});
        if (candidate != null) {
            titleFont = candidate;
        }
        candidate = Gfx.getVectorFont({:face => "RobotoRegular", :size => 26});
        if (candidate != null) {
            taskFont = candidate;
        }
        candidate = Gfx.getVectorFont({:face => "RobotoRegular", :size => 23});
        if (candidate != null) {
            metaFont = candidate;
        }
        candidate = Gfx.getVectorFont({:face => "RobotoRegular", :size => 20});
        if (candidate != null) {
            statusFont = candidate;
        }
        candidate = Gfx.getVectorFont({:face => "RobotoRegular", :size => 21});
        if (candidate != null) {
            navFont = candidate;
        }
    }

    function color(compact, rich, fallback) {
        if (compact) {
            return fallback;
        }
        if (isReferenceSize(screenWidth, screenHeight)) {
            if (rich == SURFACE) {
                return REFERENCE_SURFACE;
            }
            if (rich == TEXT) {
                return Gfx.COLOR_WHITE;
            }
        }
        return rich;
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
            return color(compact, KLEIN, Gfx.COLOR_WHITE);
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
            if (task["isOverdue"] == true) {
                return "Overdue  " + due.substring(5, 10);
            }
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
        taskHeight = isReferenceSize(width, height) ? 30 : bodyFontHeight;
        rowBounds = [];
        nodeBounds = [];
        navBounds = [];
        actionBounds = null;
        actionKind = null;
        listTop = 0;
        rowHeight = 0;
        var compact = isCompactSize(width, height);
        listTop = isReferenceSize(width, height) ? 124 : headerTop(height, compact) + titleHeight + bodyHeight + (compact ? 4 : 8);
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
            var actionY = navBounds[0][1] - (compact ? 34 : 72);
            setAction("refresh", width, actionY, compact);
        }
    }

    function layoutRoute(width, height, compact) {
        var spacious = !compact && isReferenceSize(width, height);
        var navHeight = compact ? bodyHeight + 4 : (spacious ? 62 : 60);
        // The Fenix reference reserves one clean band below the route. Smaller watches retain
        // their tighter own layout instead of inheriting these display-specific coordinates.
        var bottomInset = compact ? 2 : (spacious ? 33 : height / 7 + 12);
        var navTop = height - navHeight - bottomInset;
        // The approved Fenix composition is a three-stop route. Smaller colour screens step down
        // to two rows; compact watches keep the existing button-first list.
        visibleRows = compact ? VISIBLE : (width >= 440 ? VISIBLE : 2);
        rowHeight = spacious ? 74 : (navTop - listTop) / visibleRows;
        if (rowHeight > 78) {
            rowHeight = 78;
        }
        if (rowHeight < 28) {
            rowHeight = 28;
        }
        var nodeSize = compact ? 0 : (spacious ? 48 : rowHeight - 8);
        if (nodeSize > 64) {
            nodeSize = 64;
        }
        if (!compact && nodeSize < 44) {
            nodeSize = 44;
        }
        var nodeCenter = spacious ? width * 9 / 40 : width / 7;
        var left = compact ? 6 : nodeCenter + nodeSize / 2 + (spacious ? 10 : 8);
        var right = compact ? width - 6 : (spacious ? width * 5 / 6 : width - width / 9);
        var items = controller.activeItems();
        var start = controller.selected - 1;
        if (start > items.size() - visibleRows) {
            start = items.size() - visibleRows;
        }
        if (start < 0) {
            start = 0;
        }
        for (var row = 0; row < visibleRows && start + row < items.size(); row += 1) {
            var index = start + row;
            var y = listTop + row * rowHeight;
            var itemKind = controller.mode.equals("lists") ? "list" : "task";
            var itemId = items[index]["id"];
            rowBounds.add([left, y, right - left, rowHeight, index, itemKind, itemId]);
            if (!compact) {
                var nodeY = spacious ? y + 22 : y + rowHeight / 2;
                if (!spacious && itemKind.equals("task") && dueLabel(items[index]) != null) {
                    // The reference aligns each stop with its title, not midway between title and
                    // due time. The generous stored square remains the node's touch target.
                    nodeY = y + (rowHeight - bodyHeight) / 2;
                }
                nodeBounds.add([nodeCenter - nodeSize / 2, nodeY - nodeSize / 2, nodeSize, nodeSize, index, itemKind, itemId]);
            }
        }
        var names = compact ? ["cycle"] : ["today", "inbox", "lists"];
        var navStarts = [];
        var navWidths = [];
        if (spacious) {
            // Keep the exact asymmetric centres from the approved Fenix composition.
            // The cells remain contiguous, isolated touch targets; only their widths differ.
            var firstLeft = width * 31 / 160;
            var firstWidth = width * 33 / 160;
            var secondWidth = width * 34 / 160;
            navStarts = [firstLeft, firstLeft + firstWidth, firstLeft + firstWidth + secondWidth];
            navWidths = [firstWidth, secondWidth, width * 36 / 160];
        } else {
            var navLeft = compact ? 0 : width / 10;
            var cellWidth = (width - navLeft * 2) / names.size();
            for (var index = 0; index < names.size(); index += 1) {
                navStarts.add(navLeft + index * cellWidth);
                navWidths.add(cellWidth);
            }
        }
        for (var cell = 0; cell < names.size(); cell += 1) {
            navBounds.add([navStarts[cell], navTop, navWidths[cell], navHeight, names[cell]]);
        }
    }

    function headerTop(height, compact) {
        if (compact) {
            return 8;
        }
        return height >= 440 ? 60 : height / 14;
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
                    controller.cyclePrimary(1);
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
                return tapNode(nodeBounds[node][4], nodeBounds[node][5], nodeBounds[node][6]);
            }
        }
        // A row tap selects. Retapping the selected row changes nothing.
        for (var row = 0; row < rowBounds.size(); row += 1) {
            if (contains(rowBounds[row], x, y)) {
                if (!itemMatches(rowBounds[row][4], rowBounds[row][5], rowBounds[row][6])) {
                    return true;
                }
                controller.select(rowBounds[row][4]);
                if (rowBounds[row][5].equals("list")) {
                    controller.activate();
                }
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

    function itemMatches(index, itemKind, itemId) {
        var currentKind = controller.mode.equals("lists") ? "list" : "task";
        var items = controller.activeItems();
        if (!itemKind.equals(currentKind) || index < 0 || index >= items.size()) {
            return false;
        }
        var currentId = items[index]["id"];
        return itemId instanceof String && currentId instanceof String && itemId.equals(currentId);
    }

    function tapNode(index, itemKind, itemId) {
        if (!itemMatches(index, itemKind, itemId)) {
            return true;
        }
        if (itemKind.equals("list")) {
            controller.select(index);
            controller.activate();
            return true;
        }
        if (index != controller.selected) {
            controller.select(index);
            return true;
        }
        controller.armCompletion();
        return true;
    }

    function onUpdate(dc) {
        var compact = isCompactSize(dc.getWidth(), dc.getHeight());
        prepareFonts(dc.getWidth(), dc.getHeight());
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
        var spacious = !compact && width >= 440 && dc.getHeight() >= 440;
        dc.setColor(color(compact, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, top, titleFont, fitText(dc, modeTitle(), titleFont, width - (compact ? 46 : width / 4)), Gfx.TEXT_JUSTIFY_CENTER);

        var statusY = spacious ? 96 : top + titleHeight + (compact ? 1 : 2);
        var statusText = statusLabel();
        var fitted = fitText(dc, statusText, statusFont, width - (compact ? 24 : width / 4));
        dc.setColor(statusColor(compact), Gfx.COLOR_TRANSPARENT);
        if (!compact) {
            dc.setColor(KLEIN, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(width / 2 - dc.getTextWidthInPixels(fitted, statusFont) / 2 - 7, statusY + dc.getFontHeight(statusFont) / 2, 3);
            dc.setColor(statusColor(compact), Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(width / 2 + (compact ? 0 : 5), statusY, statusFont, fitted, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawFolderMark(dc, centerX, centerY) {
        dc.drawLine(centerX - 10, centerY - 7, centerX - 3, centerY - 7);
        dc.drawLine(centerX - 3, centerY - 7, centerX, centerY - 3);
        dc.drawLine(centerX, centerY - 3, centerX + 10, centerY - 3);
        dc.drawLine(centerX + 10, centerY - 3, centerX + 10, centerY + 8);
        dc.drawLine(centerX + 10, centerY + 8, centerX - 10, centerY + 8);
        dc.drawLine(centerX - 10, centerY + 8, centerX - 10, centerY - 7);
    }

    // A route, not a stack of cards: one spine, one stop per task, the selected action lit.
    function drawRoute(dc) {
        var items = controller.activeItems();
        var isLists = controller.mode.equals("lists");
        var spineX = nodeBounds[0][0] + nodeBounds[0][2] / 2;
        var firstY = nodeBounds[0][1] + nodeBounds[0][3] / 2;
        var lastNode = nodeBounds[nodeBounds.size() - 1];
        if (!isLists) {
            dc.setColor(MUTED, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(spineX, firstY, spineX, lastNode[1] + lastNode[3] / 2);
        }

        for (var row = 0; row < rowBounds.size(); row += 1) {
            var bounds = rowBounds[row];
            var index = bounds[4];
            var item = items[index];
            var selected = index == controller.selected;
            var node = nodeBounds[row];
            var centerY = node[1] + node[3] / 2;

            if (!isLists && selected && row + 1 < nodeBounds.size()) {
                dc.setColor(CORAL, Gfx.COLOR_TRANSPARENT);
                var nextNode = nodeBounds[row + 1];
                dc.drawLine(spineX, centerY, spineX, nextNode[1] + nextNode[3] / 2);
            }
            if (row + 1 < rowBounds.size()) {
                dc.setColor(HAIRLINE, Gfx.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                var dividerY = bounds[1] + bounds[3] - (isReferenceSize(screenWidth, screenHeight) ? 3 : 0);
                dc.drawLine(bounds[0], dividerY, bounds[0] + bounds[2], dividerY);
                dc.setPenWidth(2);
            }

            dc.setColor(color(false, SURFACE, Gfx.COLOR_BLACK), Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(spineX, centerY, isReferenceSize(screenWidth, screenHeight) ? 11 : 12);
            dc.setColor(selected ? CORAL : MUTED, Gfx.COLOR_TRANSPARENT);
            if (isLists) {
                drawFolderMark(dc, spineX, centerY);
            } else {
                dc.drawCircle(spineX, centerY, isReferenceSize(screenWidth, screenHeight) ? 10 : 11);
                if (selected) {
                    dc.fillCircle(spineX, centerY, isReferenceSize(screenWidth, screenHeight) ? 5 : 6);
                }
            }

            var label = isLists ? item["name"] : item["title"];
            var due = isLists ? null : dueLabel(item);
            var textX = bounds[0];
            var textWidth = bounds[2];
            var textY = isReferenceSize(screenWidth, screenHeight) ? bounds[1] + 6 : (due == null ? centerY - bodyHeight / 2 : bounds[1] + (bounds[3] - bodyHeight * 2) / 2);
            dc.setColor(color(false, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
            dc.drawText(textX, textY, taskFont, fitText(dc, label, taskFont, textWidth), Gfx.TEXT_JUSTIFY_LEFT);
            if (due != null) {
                dc.setColor(MUTED, Gfx.COLOR_TRANSPARENT);
                dc.drawText(textX, textY + taskHeight + 1, metaFont, fitText(dc, due, metaFont, textWidth), Gfx.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.setPenWidth(1);
    }

    function navLabel(name) {
        if (name.equals("inbox")) {
            return "Inbox";
        }
        return name.equals("lists") ? "Lists" : "Today";
    }

    function navActive(name) {
        if (name.equals("lists")) {
            return controller.mode.equals("lists") || controller.mode.equals("project");
        }
        return controller.mode.equals(name);
    }

    function drawNavIcon(dc, name, centerX, centerY) {
        if (name.equals("today")) {
            dc.drawRoundedRectangle(centerX - 10, centerY - 8, 20, 18, 3);
            dc.drawLine(centerX - 6, centerY - 11, centerX - 6, centerY - 5);
            dc.drawLine(centerX + 6, centerY - 11, centerX + 6, centerY - 5);
            dc.drawLine(centerX - 9, centerY - 2, centerX + 9, centerY - 2);
            return;
        }
        if (name.equals("inbox")) {
            dc.drawLine(centerX - 11, centerY - 8, centerX - 11, centerY + 8);
            dc.drawLine(centerX - 11, centerY + 8, centerX + 11, centerY + 8);
            dc.drawLine(centerX + 11, centerY + 8, centerX + 11, centerY - 8);
            dc.drawLine(centerX - 11, centerY - 8, centerX - 4, centerY - 8);
            dc.drawLine(centerX + 4, centerY - 8, centerX + 11, centerY - 8);
            dc.drawLine(centerX - 4, centerY - 8, centerX, centerY - 3);
            dc.drawLine(centerX, centerY - 3, centerX + 4, centerY - 8);
            return;
        }
        dc.drawLine(centerX - 11, centerY - 7, centerX - 3, centerY - 7);
        dc.drawLine(centerX - 3, centerY - 7, centerX, centerY - 3);
        dc.drawLine(centerX, centerY - 3, centerX + 11, centerY - 3);
        dc.drawLine(centerX + 11, centerY - 3, centerX + 11, centerY + 9);
        dc.drawLine(centerX + 11, centerY + 9, centerX - 11, centerY + 9);
        dc.drawLine(centerX - 11, centerY + 9, centerX - 11, centerY - 7);
    }

    function drawNavigation(dc) {
        dc.setColor(HAIRLINE, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(navBounds[0][0], navBounds[0][1], navBounds[navBounds.size() - 1][0] + navBounds[navBounds.size() - 1][2], navBounds[0][1]);
        for (var cell = 0; cell < navBounds.size(); cell += 1) {
            var bounds = navBounds[cell];
            var name = bounds[4];
            var active = navActive(name);
            var centerX = bounds[0] + bounds[2] / 2;
            if (active) {
                dc.setColor(KLEIN, Gfx.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                var indicatorHalfWidth = isReferenceSize(screenWidth, screenHeight) ? 24 : 30;
                dc.drawLine(centerX - indicatorHalfWidth, bounds[1], centerX + indicatorHalfWidth, bounds[1]);
                dc.setPenWidth(1);
            }
            dc.setColor(active ? KLEIN : MUTED, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            drawNavIcon(dc, name, centerX, bounds[1] + 22);
            dc.setPenWidth(1);
            dc.setColor(active ? KLEIN : color(false, TEXT, Gfx.COLOR_WHITE), Gfx.COLOR_TRANSPARENT);
            var labelY = isReferenceSize(screenWidth, screenHeight) ? bounds[1] + 40 : bounds[1] + bounds[3] - bodyHeight - 1;
            dc.drawText(centerX, labelY, navFont, navLabel(name), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawCompactRows(dc) {
        var items = controller.activeItems();
        for (var row = 0; row < rowBounds.size(); row += 1) {
            var bounds = rowBounds[row];
            var index = bounds[4];
            var item = items[index];
            var label = controller.mode.equals("lists") ? item["name"] : item["title"];
            dc.setColor(index == controller.selected ? Gfx.COLOR_WHITE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(bounds[0], bounds[1], Gfx.FONT_XTINY, (index == controller.selected ? "> " : "  ") + fitText(dc, label, Gfx.FONT_XTINY, bounds[2] - 12), Gfx.TEXT_JUSTIFY_LEFT);
        }
        drawCompactNavigation(dc);
    }

    function drawCompactNavigation(dc) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        var footer = navBounds[0];
        var label = "MENU " + navLabel(controller.mode.equals("project") ? "lists" : controller.mode);
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
        var emptyLabel = controller.mode.equals("lists") ? "No lists" : (controller.mode.equals("inbox") ? "Inbox clear" : "All clear");
        var top = drawCenteredBlock(dc, compact, [emptyLabel]);
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
