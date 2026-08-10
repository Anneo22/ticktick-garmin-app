class OfflineQueue {
    const MAX_MUTATIONS = 8;
    var store;

    function initialize(localStore) {
        store = localStore;
    }

    function size() {
        return store.getQueue().size();
    }

    function enqueueComplete(task, mutationId) {
        var queue = store.getQueue();
        if (queue.size() >= MAX_MUTATIONS) {
            return false;
        }
        queue.add({
            "type" => "complete",
            "taskId" => task["id"],
            "projectId" => task["projectId"],
            "mutationId" => mutationId
        });
        store.setQueue(queue);
        return true;
    }

    function head() {
        var queue = store.getQueue();
        return queue.size() == 0 ? null : queue[0];
    }

    function removeHead() {
        var queue = store.getQueue();
        if (queue.size() > 0) {
            queue.remove(queue[0]);
            store.setQueue(queue);
        }
    }
}
