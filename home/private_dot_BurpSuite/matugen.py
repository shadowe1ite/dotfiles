from burp import IBurpExtender, IExtensionStateListener
from java.awt import Color, Window
from javax.swing import UIManager, SwingUtilities
import json
import os
import sys

THEME_FILE_PATH = os.path.expanduser("~/.config/burp/material.json")
# =======================================================

class BurpExtender(IBurpExtender, IExtensionStateListener):
    
    def registerExtenderCallbacks(self, callbacks):
        self._callbacks = callbacks
        self._helpers = callbacks.getHelpers()
        callbacks.setExtensionName("Matugen Theme Loader")
        callbacks.registerExtensionStateListener(self)
        
        print("[-] Theme Loader: Extension Loaded.")
        print("[-] Theme Loader: Target config file: " + THEME_FILE_PATH)
        
        SwingUtilities.invokeLater(self.apply_theme)

    def extensionUnloaded(self):
        print("[-] Theme Loader: Unloaded.")

    def hex_to_color(self, hex_str):
        """Converts #RRGGBB or #RRGGBBAA to java.awt.Color"""
        try:
            if not isinstance(hex_str, basestring):
                return None
            hex_str = hex_str.strip().lstrip('#')
            if len(hex_str) == 6:
                r = int(hex_str[0:2], 16)
                g = int(hex_str[2:4], 16)
                b = int(hex_str[4:6], 16)
                return Color(r, g, b)
            elif len(hex_str) == 8:
                r = int(hex_str[0:2], 16)
                g = int(hex_str[2:4], 16)
                b = int(hex_str[4:6], 16)
                a = int(hex_str[6:8], 16)
                return Color(r, g, b, a)
        except Exception as e:
            # Silently fail for invalid colors to avoid console spam
            pass
        return None

    def flatten_json(self, data, prefix=""):
        """Recursively flattens JSON to match UIManager keys (e.g. Button.background)"""
        flattened = {}
        
        for key, value in data.items():
            # Handle the wildcard block "*" by treating children as root-level keys if needed, 
            # or just skip the asterisk in the naming path.
            current_key = key if key != "*" else ""
            
            # Combine prefix (e.g., "Button" + "." + "background")
            if prefix and current_key:
                full_key = prefix + "." + current_key
            elif prefix:
                full_key = prefix
            else:
                full_key = current_key

            if isinstance(value, dict):
                # Recurse if it's a nested object
                flattened.update(self.flatten_json(value, full_key))
            elif isinstance(value, basestring):
                # It's a value, add it to our map
                flattened[full_key] = value
                
        return flattened

    def apply_theme(self):
        try:
            if not os.path.exists(THEME_FILE_PATH):
                print("[-] ERROR: Theme file not found at: " + THEME_FILE_PATH)
                return

            # 1. Read the JSON file
            with open(THEME_FILE_PATH, 'r') as f:
                content = f.read()
                data = json.loads(content)

            # 2. Extract the 'ui' block if it exists, otherwise assume root
            ui_data = data.get("ui", data)

            # 3. Flatten the keys
            flat_keys = self.flatten_json(ui_data)
            
            count = 0
            # 4. Apply to UIManager
            for key, hex_val in flat_keys.items():
                if hex_val.startswith("#"):
                    color = self.hex_to_color(hex_val)
                    if color:
                        UIManager.put(key, color)
                        count += 1

            print("[-] Success! Applied " + str(count) + " theme keys.")

            # 5. Force UI Update on all open windows
            for window in Window.getWindows():
                SwingUtilities.updateComponentTreeUI(window)
                if window.isDisplayable():
                    window.repaint()
            
            print("[-] UI Refresh Triggered.")

        except Exception as e:
            print("[-] Error applying theme: " + str(e))
            import traceback
            traceback.print_exc()
