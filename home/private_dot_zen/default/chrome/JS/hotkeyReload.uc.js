// UserScript
// @name         userChrome.css Hot Reload (Hotkey Only)
// @namespace    userChrome.js
// @description  Reload userChrome.css only when hotkey is pressed.
// @version      8.1
// @include      chrome://browser/content/browser.xhtml
// @grant        none
// /UserScript

(function () {
  "use strict";

  const userChromeReloader = {
    sss: null,
    userChromeURI: null,
    userChromeFile: null,

    init() {
      try {
        this.sss = Components.classes[
          "@mozilla.org/content/style-sheet-service;1"
        ].getService(Components.interfaces.nsIStyleSheetService);

        const profileDir = Services.dirsvc.get(
          "ProfD",
          Components.interfaces.nsIFile,
        );
        const chromeDir = profileDir.clone();
        chromeDir.append("chrome");

        this.userChromeFile = chromeDir.clone();
        this.userChromeFile.append("userChrome.css");

        if (!this.userChromeFile.exists()) return;

        this.userChromeURI = Services.io.newFileURI(this.userChromeFile);

        // Alt + Shift + R hotkey
        window.addEventListener("keydown", (e) => {
          if (e.altKey && e.shiftKey && e.code === "KeyR") {
            e.preventDefault();
            this.reloadUserChrome();
          }
        });

      } catch (e) {
        console.error(e);
      }
    },

    reloadUserChrome() {
      try {
        const cssContent = this.readUserChromeFile();
        this.reloadWithStyleSheetService();
        this.applyCSSDirect(cssContent);
        this.forceUIRefresh();
      } catch (e) {
        console.error(e);
      }
    },

    reloadWithStyleSheetService() {
      const types = [this.sss.USER_SHEET, this.sss.AGENT_SHEET];

      for (const sheetType of types) {
        if (this.sss.sheetRegistered(this.userChromeURI, sheetType)) {
          this.sss.unregisterSheet(this.userChromeURI, sheetType);
        }
        this.sss.loadAndRegisterSheet(this.userChromeURI, sheetType);
      }
    },

    applyCSSDirect(cssContent) {
      if (!cssContent) return;

      const styleId = "userChrome-hot-reload-direct";
      let styleElement = document.getElementById(styleId);

      if (!styleElement) {
        styleElement = document.createElement("style");
        styleElement.id = styleId;
        document.documentElement.appendChild(styleElement);
      }

      styleElement.textContent =
        `/* hot-reload ${Date.now()} */\n` + cssContent;
    },

    forceUIRefresh() {
      Services.obs.notifyObservers(null, "chrome-flush-caches", null);
      Services.obs.notifyObservers(null, "chrome-flush-skin-caches", null);
      Services.obs.notifyObservers(null, "startupcache-invalidate", null);

      document.documentElement.style.animation = "none";
      setTimeout(() => {
        document.documentElement.style.animation = "";
      }, 50);

      void document.documentElement.offsetHeight;
    },

    readUserChromeFile() {
      try {
        const fis = Components.classes[
          "@mozilla.org/network/file-input-stream;1"
        ].createInstance(Components.interfaces.nsIFileInputStream);
        fis.init(this.userChromeFile, 0x01, 0o444, 0);

        const cis = Components.classes[
          "@mozilla.org/intl/converter-input-stream;1"
        ].createInstance(Components.interfaces.nsIConverterInputStream);
        cis.init(fis, "UTF-8", 1024, 0);

        let content = "";
        let str = {};
        while (cis.readString(4096, str) !== 0) {
          content += str.value;
        }

        cis.close();
        fis.close();
        return content;
      } catch (e) {
        console.error(e);
        return null;
      }
    },
  };

  if (gBrowserInit.delayedStartupFinished) {
    userChromeReloader.init();
  } else {
    const listener = (subject, topic) => {
      if (topic === "browser-delayed-startup-finished" && subject === window) {
        Services.obs.removeObserver(listener, topic);
        userChromeReloader.init();
      }
    };
    Services.obs.addObserver(listener, "browser-delayed-startup-finished");
  }
})();
