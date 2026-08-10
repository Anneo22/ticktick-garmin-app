import Toybox.Test;
import Toybox.Lang;

class QueueTestStore {
    var values;

    function initialize() {
        values = [];
    }

    function getQueue() {
        return values;
    }

    function setQueue(queue) {
        values = queue;
    }
}

(:test)
function offlineQueueIsFifo(logger as Test.Logger) as Boolean {
    var store = new QueueTestStore();
    var queue = new OfflineQueue(store);
    queue.enqueueComplete({"id" => "one", "projectId" => "project"}, "mutation-one");
    queue.enqueueComplete({"id" => "two", "projectId" => "project"}, "mutation-two");
    Test.assertEqual("mutation-one", queue.head()["mutationId"]);
    queue.removeHead();
    Test.assertEqual("mutation-two", queue.head()["mutationId"]);
    return true;
}

(:test)
function offlineQueueRefusesOverflow(logger as Test.Logger) as Boolean {
    var store = new QueueTestStore();
    var queue = new OfflineQueue(store);
    for (var index = 0; index < 8; index += 1) {
        var id = index.format("%d");
        Test.assert(queue.enqueueComplete({"id" => id, "projectId" => "project"}, "mutation-" + id));
    }
    Test.assertEqual(8, queue.size());
    Test.assert(!queue.enqueueComplete({"id" => "overflow", "projectId" => "project"}, "mutation-overflow"));
    Test.assertEqual(8, queue.size());
    return true;
}
