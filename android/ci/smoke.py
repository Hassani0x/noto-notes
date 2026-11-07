"""Exercise the Android notebook on a connected test emulator."""
import subprocess
import time
import re
import xml.etree.ElementTree as ET
from pathlib import Path

def adb(*args):
    return subprocess.check_output(["adb", *args], text=True)

def screen():
    adb("shell", "uiautomator", "dump", "/sdcard/noto-hierarchy.xml")
    return ET.fromstring(adb("shell", "cat", "/sdcard/noto-hierarchy.xml"))

def tap(label):
    for attempt in range(3):
        for item in screen().iter("node"):
            if label in (item.get("text"), item.get("content-desc")):
                x, y, right, bottom = map(int, re.findall(r"\d+", item.get("bounds")))
                adb("shell", "input", "tap", str((x+right)//2), str((y+bottom)//2))
                return
        time.sleep(1)
    raise AssertionError("Missing control: " + label)

def capture(name):
    Path("screens").mkdir(exist_ok=True)
    with open("screens/" + name + ".png", "wb") as f:
        subprocess.run(["adb","exec-out","screencap","-p"],stdout=f,check=True)

adb("shell","am","start","-n","app.hassani.noto/.Notebook")
tap("＋  New note")
tap("Title")
adb("shell","input","text","Sketchbook")
adb("shell","input","keyevent","4")
tap("Write a note")
adb("shell","input","text","Try%sa%snew%scolor%sfor%sthe%scover.")
adb("shell","input","keyevent","4")
tap("Options")
tap("Note settings")
tap("Change filing date")
tap("Cancel")
tap("Options")
tap("Note settings")
tap("Paper color")
tap("Sky")
tap("Options")
tap("Note settings")
tap("Move to folder")
tap("Ideas")
texts=[n.get("text","") for n in screen().iter("node")]
assert "Change filing date" not in texts and not any(re.fullmatch(r"\d{4}-\d\d-\d\d",t) for t in texts)
capture("editor")
tap("‹ Notes")
tap("＋  New note")
tap("Title")
adb("shell","input","text","Weekend%splans")
adb("shell","input","keyevent","4")
tap("‹ Notes")
tap("Sketchbook")
tap("‹ Notes")
capture("notebook")

