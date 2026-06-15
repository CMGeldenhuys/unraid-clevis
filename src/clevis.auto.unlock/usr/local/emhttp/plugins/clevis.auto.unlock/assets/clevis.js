/* Clevis Auto-Unlock — dashboard logic. Vanilla JS (fetch). All POSTs carry the
 * Unraid CSRF token. Device-supplied strings are rendered via textContent (no XSS).
 *
 * Feedback model: requests NEVER reject — post()/get() always resolve to an object
 * ({ok:false,error:...} on any failure). A clicked button shows a non-blocking busy
 * state; SweetAlert (v1, modal) is used ONLY for the final result, so it can't be
 * swallowed by an open "working" dialog. */
(function () {
  "use strict";
  var CAU = window.CAU || {};
  var $ = function (id) { return document.getElementById(id); };

  function parseJson(r) {
    return r.text().then(function (t) {
      try { return JSON.parse(t); }
      catch (e) { return { ok: false, error: "HTTP " + r.status + ": " + String(t || r.statusText).slice(0, 300) }; }
    });
  }
  /* POST as application/x-www-form-urlencoded (URLSearchParams), NOT multipart/FormData.
   * Unraid fronts every plugin endpoint with an nginx `auth_request` to /auth-request.php,
   * and that auth subrequest HANGS on a multipart/form-data body — php-fpm blocks reading a
   * body nginx never forwards to the subrequest, so the gate times out (≈60s) and EVERY POST
   * 504s before our code runs. urlencoded is what the native webGUI sends and it passes the
   * gate cleanly. Do NOT switch this back to FormData. (URLSearchParams shares .append().) */
  function post(endpoint, data) {
    var body = new URLSearchParams();
    body.append("csrf_token", CAU.csrf);
    Object.keys(data || {}).forEach(function (k) { body.append(k, data[k]); });
    return fetch(CAU.base + "/" + endpoint, { method: "POST", body: body, credentials: "same-origin" })
      .then(parseJson).catch(function (e) { return { ok: false, error: "request failed: " + e }; });
  }
  function get(endpoint) {
    return fetch(CAU.base + "/" + endpoint, { credentials: "same-origin" })
      .then(parseJson).catch(function (e) { return { ok: false, error: "request failed: " + e }; });
  }

  /* final result dialog (SweetAlert v1 if present) */
  function show(ok, msg) {
    if (window.swal) swal({ title: ok ? "Success" : "Error", text: msg, type: ok ? "success" : "error" });
    else alert((ok ? "OK: " : "Error: ") + msg);
  }
  /* non-blocking busy state on the clicked button */
  function busy(btn, on) { if (btn) { btn.disabled = on; btn.classList.toggle("cau-busy", on); } }
  /* run an action: busy → post → result → refresh status */
  function action(btn, endpoint, data, onResult) {
    busy(btn, true);
    post(endpoint, data).then(function (r) { busy(btn, false); onResult(r); loadStatus(); });
  }
  function banner(el, kind, text) {
    el.className = "cau-banner" + (kind ? " cau-" + kind : "");
    el.textContent = text;
    el.style.display = text ? "block" : "none";
  }

  /* --- rendering --- */
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
  var TANG = {
    unconfigured: ["cau-muted",     "fa-circle-o",            "not configured"],
    unreachable:  ["cau-bad",       "fa-times-circle",        "unreachable"],
    reachable:    ["cau-yes",       "fa-check-circle",        "reachable"],
    ok:           ["cau-yes",       "fa-check-circle",        "reachable · key pinned"],
    "thp-changed":["cau-warn-text", "fa-exclamation-triangle","key changed — re-pin"]
  };
  function renderTangStatus(h) {
    var el = $("cau-tang-status"); if (!el) return;
    var s = TANG[(h && h.state)] || TANG.unconfigured;
    el.className = "cau-status " + s[0];
    el.innerHTML = "";
    var ic = document.createElement("i"); ic.className = "fa " + s[1];
    el.appendChild(ic); el.appendChild(document.createTextNode(" tang: " + s[2]));
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
      tr.appendChild(cell(d.name)); tr.appendChild(cell(d.device)); tr.appendChild(yesno(d.is_luks));
      tb.appendChild(tr);
    });
  }

  function loadHealth() {
    get("Health.php").then(function (h) {
      renderTangStatus(h);
      var el = $("cau-health");
      if (!h || ["unconfigured", "reachable", "ok"].indexOf(h.state) !== -1) { el.style.display = "none"; }
      else if (h.state === "unreachable") banner(el, "warn", "Tang server unreachable — the array will not auto-unlock until it is back.");
      else if (h.state === "thp-changed") banner(el, "alert", "Tang no longer advertises the pinned key. If you did not rotate it, investigate. Use Rotate to re-pin.");
      else banner(el, "", "");
    });
  }
  function loadStatus() {
    get("Status.php").then(function (s) {
      if (!s || s.error) { banner($("cau-status"), "alert", "Could not read status: " + ((s && s.error) || "unknown")); return; }
      if (s.tools && (!s.tools.clevis || !s.tools.jose))
        banner($("cau-health"), "alert", "clevis/jose are not available — the bundled packages may have failed to install for this Unraid version.");
      renderConfig(s.config || {});
      renderDevices(s.devices || []);
    });
    loadHealth();
  }

  /* --- actions --- */
  function save() {
    action($("cau-save"), "SaveConfig.php", {
      url: $("cau-url").value.trim(), enabled: $("cau-enabled").value,
      unlock_mode: $("cau-mode").value, network_timeout: $("cau-timeout").value
    }, function (r) { show(r.ok, r.ok ? "Settings saved." : ("Save failed: " + (r.error || ""))); });
  }
  function seal() {
    var pass = $("cau-pass").value;
    if (!pass) { show(false, "Enter your array passphrase first."); return; }
    if (location.protocol !== "https:" && !confirm("The webGUI is not using HTTPS. Your passphrase would be sent unencrypted. Continue?")) return;
    action($("cau-seal"), "Seal.php", { url: $("cau-url").value.trim(), passphrase: pass }, function (r) {
      $("cau-pass").value = "";
      show(r.ok, r.ok ? ("Passphrase sealed for " + r.devices + " device(s). Auto-unlock is armed.")
                      : ("Seal failed: " + (r.error || "unknown")));
    });
  }
  function test() {
    action($("cau-test"), "TestUnlock.php", {}, function (r) {
      if (r.results && r.results.length) {
        var lines = r.results.map(function (x) { return x.device + ": " + (x.opens ? "opens ✓" : "FAIL ✗"); }).join("\n");
        show(!!r.ok, (r.ok ? "Dry-run passed — auto-unlock will work:\n" : "Dry-run FAILED:\n") + lines);
      } else {
        show(false, "Nothing to test: " + (r.error || "seal a passphrase first, or no encrypted devices"));
      }
    });
  }
  function rotate() {
    if (!confirm("Re-seal the passphrase to the tang server's current key?")) return;
    action($("cau-rotate"), "Rotate.php", { url: $("cau-url").value.trim() }, function (r) {
      show(r.ok, r.ok ? "Re-pinned to the current tang key." : ("Rotate failed: " + (r.error || "")));
    });
  }
  function forget() {
    if (!confirm("Remove the sealed passphrase and disable auto-unlock? Disk encryption is unchanged.")) return;
    action($("cau-forget"), "Forget.php", {}, function (r) {
      show(r.ok, r.ok ? "Sealed passphrase removed; auto-unlock disabled." : ("Failed: " + (r.error || "")));
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (location.protocol !== "https:") $("cau-https-warning").style.display = "block";
    $("cau-save").addEventListener("click", save);
    $("cau-seal").addEventListener("click", seal);
    $("cau-test").addEventListener("click", test);
    $("cau-rotate").addEventListener("click", rotate);
    $("cau-forget").addEventListener("click", forget);
    $("cau-refresh").addEventListener("click", loadStatus);
    $("cau-check").addEventListener("click", loadHealth);
    loadStatus();
  });
})();
