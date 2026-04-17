// iMessage Web UI — Client Application

(function () {
  "use strict";

  // ---- State ----

  let chats = [];
  let currentChatId = null;
  let currentChatInfo = null;
  let messages = [];
  let ws = null;
  let wsReconnectDelay = 1000;
  let contactMap = {};
  let messageCache = {};
  let refreshChatListTimer = null;

  // ---- DOM refs ----

  const chatListEl = document.getElementById("chat-list");
  const messagesEl = document.getElementById("messages");
  const titleEl = document.getElementById("conversation-title");
  const composeEl = document.getElementById("compose");
  const inputEl = document.getElementById("message-input");
  const sendBtn = document.getElementById("send-btn");
  const searchEl = document.getElementById("search");
  const sidebarEl = document.getElementById("sidebar");
  const backBtn = document.getElementById("back-btn");

  // ---- API ----

  async function fetchChats() {
    const res = await fetch("/api/chats?limit=100");
    const data = await res.json();
    return data.chats || [];
  }

  async function fetchMessages(chatId, limit) {
    limit = limit || 100;
    const res = await fetch(
      "/api/chats/" + chatId + "/messages?limit=" + limit + "&attachments=true"
    );
    const data = await res.json();
    return data.messages || [];
  }

  async function sendMessage(text) {
    if (!currentChatInfo) return;
    const body = { text: text };
    if (currentChatInfo.guid) {
      body.chat_guid = currentChatInfo.guid;
    } else if (currentChatInfo.identifier) {
      body.chat_identifier = currentChatInfo.identifier;
    } else if (
      currentChatInfo.participants &&
      currentChatInfo.participants.length === 1
    ) {
      body.to = currentChatInfo.participants[0];
    } else {
      body.chat_id = currentChatId;
    }

    await fetch("/api/send", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  async function fetchContacts() {
    try {
      const res = await fetch("/api/contacts");
      const data = await res.json();
      contactMap = data.contacts || {};
    } catch (e) {
      contactMap = {};
    }
  }

  function resolveHandle(handle) {
    if (!handle) return handle;
    // Exact match
    if (contactMap[handle]) return contactMap[handle];
    // Case-insensitive (email)
    var lower = handle.toLowerCase();
    if (contactMap[lower]) return contactMap[lower];
    // Last-10-digits match (phone)
    var digits = handle.replace(/\D/g, "");
    if (digits.length >= 10) {
      var suffix = digits.slice(-10);
      if (contactMap[suffix]) return contactMap[suffix];
    }
    return handle;
  }

  function resolveParticipants(participants) {
    if (!participants || participants.length === 0) return "";
    return participants.map(resolveHandle).join(", ");
  }

  // ---- WebSocket ----

  function connectWebSocket() {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(protocol + "//" + location.host + "/ws");

    ws.onopen = function () {
      wsReconnectDelay = 1000;
      if (currentChatId !== null) {
        ws.send(JSON.stringify({ action: "subscribe", chat_id: currentChatId }));
      }
    };

    ws.onmessage = function (event) {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "message" && data.message) {
          handleIncomingMessage(data.message);
        }
      } catch (e) {
        // ignore parse errors
      }
    };

    ws.onclose = function () {
      setTimeout(function () {
        wsReconnectDelay = Math.min(wsReconnectDelay * 2, 30000);
        connectWebSocket();
      }, wsReconnectDelay);
    };

    ws.onerror = function () {
      ws.close();
    };
  }

  function handleIncomingMessage(msg) {
    // Update chat list preview (debounced to avoid flicker on rapid messages)
    debouncedRefreshChatList();

    // If the message belongs to the currently viewed chat, append it
    if (currentChatId !== null && msg.chat_id === currentChatId) {
      // Avoid duplicates
      if (!messages.some(function (m) { return m.guid === msg.guid; })) {
        messages.push(msg);
        // Update cache
        if (messageCache[currentChatId]) {
          messageCache[currentChatId].messages = messages.slice();
          messageCache[currentChatId].fetchedAt = Date.now();
        }
        renderMessages();
        scrollToBottom();
      }
    }
  }

  // ---- Rendering: Chat List ----

  function renderChatList(filter) {
    filter = (filter || "").toLowerCase();
    chatListEl.innerHTML = "";

    const filtered = chats.filter(function (chat) {
      if (!filter) return true;
      var resolved = resolveParticipants(chat.participants);
      return (
        (chat.name && chat.name.toLowerCase().includes(filter)) ||
        (resolved && resolved.toLowerCase().includes(filter)) ||
        (chat.participants &&
          chat.participants.some(function (p) {
            return p.toLowerCase().includes(filter);
          }))
      );
    });

    filtered.forEach(function (chat) {
      const row = document.createElement("div");
      row.className = "chat-row" + (chat.id === currentChatId ? " selected" : "");
      row.onclick = function () {
        selectChat(chat);
      };

      const displayName = chat.name || resolveParticipants(chat.participants) || resolveHandle(chat.identifier);
      const initials = getInitials(displayName);
      const color = avatarColor(displayName);

      row.innerHTML =
        '<div class="chat-avatar" style="background:' + color + '">' + escapeHtml(initials) + "</div>" +
        '<div class="chat-info">' +
          '<div class="chat-top-row">' +
            '<span class="chat-name">' + escapeHtml(displayName) + "</span>" +
            '<span class="chat-time">' + formatChatTime(chat.last_message_at) + "</span>" +
          "</div>" +
        "</div>";

      chatListEl.appendChild(row);
    });
  }

  // ---- Rendering: Messages ----

  function renderMessages() {
    messagesEl.innerHTML = "";

    if (messages.length === 0) {
      messagesEl.innerHTML = '<div class="empty-state">No messages</div>';
      return;
    }

    let lastDate = null;
    let lastSender = null;
    let lastIsFromMe = null;

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i];
      const msgDate = new Date(msg.created_at);

      // Skip reaction events
      if (msg.is_reaction) continue;

      // Timestamp divider
      const dateKey = formatDateKey(msgDate);
      if (dateKey !== lastDate) {
        const divider = document.createElement("div");
        divider.className = "timestamp-divider";
        divider.textContent = formatTimestamp(msgDate);
        messagesEl.appendChild(divider);
        lastDate = dateKey;
        lastSender = null;
        lastIsFromMe = null;
      }

      // Sender label for group chats (received only)
      const isGroup = currentChatInfo && currentChatInfo.is_group;
      if (isGroup && !msg.is_from_me && msg.sender !== lastSender) {
        const senderEl = document.createElement("div");
        senderEl.className = "message-sender";
        senderEl.textContent = resolveHandle(msg.sender);
        messagesEl.appendChild(senderEl);
      }

      // Determine if this is the tail (last in a group from same sender)
      const nextMsg = messages[i + 1];
      const isTail =
        !nextMsg ||
        nextMsg.is_from_me !== msg.is_from_me ||
        nextMsg.sender !== msg.sender ||
        nextMsg.is_reaction ||
        timeDiffMinutes(msgDate, new Date(nextMsg.created_at)) > 1;

      const row = document.createElement("div");
      row.className =
        "message-row " +
        (msg.is_from_me ? "sent" : "received") +
        (isTail ? " tail" : "");

      const bubble = document.createElement("div");
      bubble.className = "message-bubble";
      bubble.textContent = msg.text || "";

      row.appendChild(bubble);

      // Reactions
      if (msg.reactions && msg.reactions.length > 0) {
        const reactionsEl = document.createElement("div");
        reactionsEl.className = "message-reactions";
        msg.reactions.forEach(function (r) {
          const badge = document.createElement("span");
          badge.className = "reaction-badge";
          badge.textContent = r.emoji;
          reactionsEl.appendChild(badge);
        });
        row.appendChild(reactionsEl);
      }

      messagesEl.appendChild(row);
      lastSender = msg.sender;
      lastIsFromMe = msg.is_from_me;
    }
  }

  // ---- Actions ----

  async function selectChat(chat) {
    currentChatId = chat.id;
    currentChatInfo = chat;

    // Update UI
    const displayName = chat.name || resolveParticipants(chat.participants) || resolveHandle(chat.identifier);
    titleEl.textContent = displayName;
    composeEl.classList.remove("hidden");
    inputEl.disabled = false;

    // Hide sidebar on mobile
    if (window.innerWidth <= 700) {
      sidebarEl.classList.add("hidden");
    }

    // Mark selected in list
    renderChatList(searchEl.value);

    // Render cached messages immediately if available, then refresh in background
    var cached = messageCache[chat.id];
    if (cached) {
      messages = cached.messages;
      renderMessages();
      scrollToBottom();
      // Fetch fresh data in background
      var chatIdAtStart = currentChatId;
      fetchMessages(chat.id).then(function (fresh) {
        if (currentChatId !== chatIdAtStart) return;
        messages = fresh;
        messageCache[chat.id] = { messages: fresh, fetchedAt: Date.now() };
        renderMessages();
        scrollToBottom();
      });
    } else {
      messagesEl.innerHTML = '<div class="empty-state">Loading\u2026</div>';
      messages = await fetchMessages(chat.id);
      messageCache[chat.id] = { messages: messages.slice(), fetchedAt: Date.now() };
      renderMessages();
      scrollToBottom();
    }

    // Subscribe via WebSocket
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ action: "subscribe", chat_id: chat.id }));
    }

    inputEl.focus();
  }

  async function doSend() {
    const text = inputEl.value.trim();
    if (!text || !currentChatId) return;

    inputEl.value = "";
    sendBtn.disabled = true;

    try {
      await sendMessage(text);
    } catch (e) {
      // Silently fail — message will appear via WebSocket if sent
    }
  }

  async function refreshChatList() {
    chats = await fetchChats();
    renderChatList(searchEl.value);
  }

  function debouncedRefreshChatList() {
    if (refreshChatListTimer) clearTimeout(refreshChatListTimer);
    refreshChatListTimer = setTimeout(function () {
      refreshChatListTimer = null;
      refreshChatList();
    }, 500);
  }

  function scrollToBottom() {
    requestAnimationFrame(function () {
      messagesEl.scrollTop = messagesEl.scrollHeight;
    });
  }

  // ---- Formatting ----

  function formatChatTime(isoString) {
    if (!isoString) return "";
    const date = new Date(isoString);
    const now = new Date();
    const diffMs = now - date;
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffDays === 0) {
      return formatTime(date);
    } else if (diffDays === 1) {
      return "Yesterday";
    } else if (diffDays < 7) {
      return dayName(date);
    } else {
      return shortDate(date);
    }
  }

  function formatTimestamp(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffDays === 0) {
      return formatTime(date);
    } else if (diffDays === 1) {
      return "Yesterday " + formatTime(date);
    } else if (diffDays < 7) {
      return dayName(date) + " " + formatTime(date);
    } else {
      return shortDate(date) + " " + formatTime(date);
    }
  }

  function formatDateKey(date) {
    return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
  }

  function formatTime(date) {
    return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  }

  function dayName(date) {
    return date.toLocaleDateString([], { weekday: "long" });
  }

  function shortDate(date) {
    return date.toLocaleDateString([], {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }

  function timeDiffMinutes(a, b) {
    return Math.abs(a - b) / 60000;
  }

  // ---- Utilities ----

  function getInitials(name) {
    if (!name) return "?";
    const parts = name.split(/[\s,]+/).filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) {
      // Could be a phone number or email
      if (/^\+?\d/.test(parts[0])) return "#";
      return parts[0][0].toUpperCase();
    }
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  const AVATAR_COLORS = [
    "#FF6B6B", "#E84393", "#A29BFE", "#6C5CE7",
    "#0984E3", "#00B894", "#00CEC9", "#FDCB6E",
    "#E17055", "#636E72", "#2D3436", "#D63031",
  ];

  function avatarColor(name) {
    let hash = 0;
    for (let i = 0; i < (name || "").length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
  }

  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  // ---- Event Listeners ----

  inputEl.addEventListener("input", function () {
    sendBtn.disabled = !inputEl.value.trim();
  });

  inputEl.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      doSend();
    }
  });

  sendBtn.addEventListener("click", function () {
    doSend();
  });

  searchEl.addEventListener("input", function () {
    renderChatList(searchEl.value);
  });

  backBtn.addEventListener("click", function () {
    sidebarEl.classList.remove("hidden");
    currentChatId = null;
    currentChatInfo = null;
    titleEl.textContent = "Messages";
    composeEl.classList.add("hidden");
    messagesEl.innerHTML = '<div class="empty-state">Select a conversation</div>';
    renderChatList(searchEl.value);

    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ action: "unsubscribe" }));
    }
  });

  // ---- Init ----

  async function init() {
    const [, fetchedChats] = await Promise.all([fetchContacts(), fetchChats()]);
    chats = fetchedChats;
    renderChatList();
    connectWebSocket();
  }

  init();
})();
