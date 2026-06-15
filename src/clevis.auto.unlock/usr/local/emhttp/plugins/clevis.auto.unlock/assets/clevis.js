/* Clevis Auto-Unlock — dashboard logic. Vanilla JS (fetch). All POSTs carry the
 * Unraid CSRF token. Device-supplied strings are rendered via textContent (no XSS). */
(function () {
  "use strict";
  var CAU = window.CAU || {};
  var $ = function (id) { return document.getElementById(id); };

  function post(endpoint, data) {
    var fd = new FormData();
    fd.append("csrf_token", CAU.csrf);
    Object.keys(data || {}).forEach(function (k) { fd.append(k, data[k]); });
    return fetch(CAU.base + "/" + endpoint, { method: "POST", body: fd, credentials: "same-origin" })
      .then(function (r) { return r.json(); });
  }
  function get(endpoint) {
    return fetch(CAU.base + "/" + endpoint, { credentials: "same-origin" }).then(function (r) { return r.json(); });
  }
  function banner(el, kind, text) {
    el.className = "cau-banner" + (kind ? " cau-" + kind : "");
    el.textContent = text;
    el.style.display = text ? "block" : "none";
  }
  function toast(msg) { if (window.swal) swal({ title: "", text: msg, animation: false }); else alert(msg); }

  function renderConfig(c) {
    $("cau-url").value = (c.tang && c.tang.url) || "";
    $("cau-enabled").value = c.enabled ? "true" : "false";
    $("cau-mode").value = c.unlock_mode || "event";
    $("cau-timeout").value = c.network_timeout || 60;
    var thp = (c.tang && c.tang.thp) || "";
    $("cau-pinned").textContent = thp ? ("pinned key: " + thp) : "no key pinned yet";
    banner($("cau-status"), c.sealed ? "ok" : "", c.sealed
      ? ("Passphrase is sealed to tang; auto-unlock is " + (c.enabled ? "ENABLED." : "configured but DISABLED."))
      : "No passphrase sealed yet — enter it below and click “Seal passphrase” to arm auto-unlock.");
  }
  function cell(t) { var td = document.createElement("td"); td.textContent = t; return td; }
  function yesno(b) { var td = cell(b ? "yes" : "no"); td.className = b ? "cau-yes" : "cau-no"; return td; }

  function renderDevices(devs) {
    var tb = $("cau-devices").querySelector("tbody");
    tb.innerHTML = "";
    if (!devs || !devs.length) {
      var tr = document.createElement("tr"), td = cell("No encrypted devices found.");
      td.colSpan = 3; td.className = "cau-muted"; tr.appendChild(td); tb.appendChild(tr); return;
    }
    devs.forEach(function (d) {
      var tr = document.createElement("tr");
      tr.appendChild(cell(d.name));
      tr.appendChild(cell(d.device));
      tr.appendChild(yesno(d.is_luks));
      tb.appendChild(tr);
    });
  }
  function loadHealth() {
    get("Health.php").then(function (h) {
      var el = $("cau-health");
      if (!h || h.reason) { el.style.display = "none"; return; }
      if (h.state === "ok") banner(el, "ok", "Tang reachable; pinned key still advertised.");
      else if (h.state === "unreachable") banner(el, "warn", "Tang server unreachable — the array will not auto-unlock until it is back.");
      else if (h.state === "thp-changed") banner(el, "alert", "Tang no longer advertises the pinned key. If you did not rotate it, investigate. Use Rotate to re-pin.");
    }).catch(function () {});
  }
  function loadStatus() {
    get("Status.php").then(function (s) {
      if (!s) return;
      if (s.tools && (!s.tools.clevis || !s.tools.jose))
        banner($("cau-health"), "alert", "clevis/jose are not available — the bundled packages may have failed to install for this Unraid version.");
      renderConfig(s.config || {});
      renderDevices(s.devices || []);
    });
    loadHealth();
  }

  function save() {
    post("SaveConfig.php", {
      url: $("cau-url").value.trim(), enabled: $("cau-enabled").value,
      unlock_mode: $("cau-mode").value, network_timeout: $("cau-timeout").value
    }).then(function (r) { toast(r.ok ? "Settings saved." : ("Save failed: " + (r.error || ""))); loadStatus(); });
  }
  function seal() {
    var pass = $("cau-pass").value;
    if (!pass) { toast("Enter your array passphrase."); return; }
    if (location.protocol !== "https:" && !confirm("The webGUI is not using HTTPS. Your passphrase would be sent unencrypted. Continue?")) return;
    toast("Sealing…");
    post("Seal.php", { url: $("cau-url").value.trim(), passphrase: pass }).then(function (r) {
      $("cau-pass").value = "";
      toast(r.ok ? ("Sealed for " + r.devices + " device(s).") : ("Seal failed: " + (r.error || "")));
      loadStatus();
    });
  }
  function test() {
    toast("Testing…");
    post("TestUnlock.php", {}).then(function (r) {
      if (!r || !r.results || !r.results.length) { toast("Nothing to test: " + ((r && r.error) || "no sealed secret or no devices")); return; }
      var msg = r.results.map(function (x) { return x.device + ": " + (x.opens ? "opens" : "FAIL"); }).join("\n");
      toast((r.ok ? "Dry-run passed:\n" : "Dry-run FAILED:\n") + msg);
    });
  }
  function rotate() {
    if (!confirm("Re-seal the passphrase to the tang server's current key?")) return;
    toast("Rotating…");
    post("Rotate.php", { url: $("cau-url").value.trim() }).then(function (r) { toast(r.ok ? "Re-pinned." : ("Rotate failed: " + (r.error || ""))); loadStatus(); });
  }
  function forget() {
    if (!confirm("Remove the sealed passphrase and disable auto-unlock? Disk encryption is unchanged.")) return;
    post("Forget.php", {}).then(function (r) { toast(r.ok ? "Forgotten." : ("Failed: " + (r.error || ""))); loadStatus(); });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (location.protocol !== "https:") $("cau-https-warning").style.display = "block";
    $("cau-save").addEventListener("click", save);
    $("cau-seal").addEventListener("click", seal);
    $("cau-test").addEventListener("click", test);
    $("cau-rotate").addEventListener("click", rotate);
    $("cau-forget").addEventListener("click", forget);
    $("cau-refresh").addEventListener("click", loadStatus);
    loadStatus();
  });
})();
