(() => {
  "use strict";

  const list = document.getElementById("tasks");
  const form = document.getElementById("new-task");
  const input = document.getElementById("title");
  const count = document.getElementById("count");
  const status = document.getElementById("status");

  function say(message, isError) {
    status.textContent = message || "";
    status.classList.toggle("error", Boolean(isError));
  }

  async function api(path, options) {
    const response = await fetch(path, options);
    if (response.status === 204) return null;
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(body.error || `request failed (${response.status})`);
    }
    return body;
  }

  function render(tasks) {
    list.replaceChildren();
    count.textContent = String(tasks.length);
    if (tasks.length === 0) {
      const empty = document.createElement("li");
      empty.className = "task";
      empty.textContent = "Nothing here yet. Add the first task.";
      list.append(empty);
      return;
    }
    for (const task of tasks) {
      const item = document.createElement("li");
      item.className = task.done ? "task done" : "task";

      const id = document.createElement("span");
      id.className = "id";
      id.textContent = `#${task.id}`;

      const title = document.createElement("span");
      title.className = "title";
      title.textContent = task.title;

      const toggle = document.createElement("button");
      toggle.type = "button";
      toggle.textContent = task.done ? "Undo" : "Done";
      toggle.addEventListener("click", () => mutate(`/api/tasks/${task.id}/toggle`, "POST"));

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "danger";
      remove.textContent = "Delete";
      remove.addEventListener("click", () => mutate(`/api/tasks/${task.id}`, "DELETE"));

      item.append(id, title, toggle, remove);
      list.append(item);
    }
  }

  async function refresh() {
    render(await api("/api/tasks"));
  }

  async function mutate(path, method) {
    try {
      await api(path, { method });
      await refresh();
      say(method === "DELETE" ? "Task deleted." : "Task updated.");
    } catch (error) {
      say(error.message, true);
    }
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const title = input.value.trim();
    if (!title) {
      say("A title is required.", true);
      input.focus();
      return;
    }
    const button = form.querySelector("button");
    button.disabled = true;
    try {
      await api("/api/tasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title }),
      });
      input.value = "";
      await refresh();
      say("Task added.");
    } catch (error) {
      say(error.message, true);
    } finally {
      button.disabled = false;
      input.focus();
    }
  });

  refresh().catch((error) => say(error.message, true));
})();
