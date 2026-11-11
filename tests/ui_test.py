"""On-screen tests for the Hours app, run against index.html in headless Chrome.
Run: python3 tests/ui_test.py   (needs: pip install playwright; a Chrome/Chromium install)
Set CHROME=/path/to/chrome if it isn't at /usr/bin/google-chrome.
"""
import asyncio, json, os, pathlib, sys
from playwright.async_api import async_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
URL = (ROOT / "index.html").as_uri()
CHROME = os.environ.get("CHROME", "/usr/bin/google-chrome")
SHOTS = os.environ.get("SHOTS")  # folder for screenshots, optional

SET = "(([id,v])=>{const el=document.getElementById(id); el.value=v; el.dispatchEvent(new Event('input')); el.dispatchEvent(new Event('change'));})"
SETB = "(([i,k,v])=>{const el=document.querySelectorAll('#breaks input')[i*2+(k==='e'?1:0)]; el.value=v; el.dispatchEvent(new Event('input')); el.dispatchEvent(new Event('change'));})"
failures = []

def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond: failures.append(msg)

class App:
    def __init__(self, p): self.p = p
    async def open(self, y, mo, d, h, mi, storage=None):
        self.b = await self.p.chromium.launch(executable_path=CHROME)
        ctx = await self.b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2,
            user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148")
        await ctx.grant_permissions(["clipboard-read", "clipboard-write"])
        init = (f"const _D=Date; const f=new _D({y},{mo-1},{d},{h},{mi}).getTime();"
                "Date=class extends _D{constructor(...a){super(...(a.length?a:[f]))} static now(){return f}};")
        await ctx.add_init_script(init)
        self.pg = await ctx.new_page()
        self.errors = []
        self.pg.on("pageerror", lambda e: self.errors.append(str(e)))
        await self.pg.goto(URL)
        if storage is not None:   # seed saved data once, then load the app fresh on top of it
            await self.pg.evaluate("s => { localStorage.clear(); localStorage.setItem('hours.v1', s); }", json.dumps(storage))
            await self.pg.reload()
        await self.pg.wait_for_function("()=>window.__hours")
        return self
    async def state(self): return json.loads(await self.pg.evaluate("()=>localStorage.getItem('hours.v1')"))
    async def close(self):
        check(not self.errors, f"no page errors {self.errors}")
        await self.b.close()
    async def set(self, id, v): await self.pg.evaluate(SET, [id, v])
    async def setb(self, i, k, v): await self.pg.evaluate(SETB, [i, k, v])
    async def txt(self, id): return await self.pg.evaluate(f"()=>document.getElementById('{id}').innerText")
    async def disabled(self): return await self.pg.evaluate("()=>document.getElementById('textBtn').classList.contains('disabled')")
    async def visible(self, id): return await self.pg.evaluate(f"()=>{{const e=document.getElementById('{id}'); return !e.hidden && getComputedStyle(e).display!=='none'}}")
    async def tap_text(self):
        await self.pg.evaluate("()=>document.getElementById('textBtn').addEventListener('click',e=>e.preventDefault(),{once:true})")
        await self.pg.click("#textBtn"); await self.pg.wait_for_timeout(500)
    async def shot(self, name):
        if SHOTS: await self.pg.screenshot(path=f"{SHOTS}/{name}.png", full_page=True)

async def main():
    async with async_playwright() as p:
        print("Monday evening: end time must be confirmed; nothing counts as sent until confirmed")
        a = await App(p).open(2026, 11, 9, 19, 5, {"entries": {}, "settings": {"name": "Mike", "phone": "9415550123", "showBrk": True}})
        await a.set("start", "09:00")
        check(await a.disabled(), "Text is blocked while the end time is the app's guess")
        check("Confirm your end time" in await a.txt("warn"), "says why")
        await a.pg.click("#endNow")
        check(not await a.disabled(), "Text unlocked after tapping Now")
        check(await a.txt("msg") == "11/9 9am-7:05pm 10hrs 5min\n10hrs 5min total for the week.", "message")
        await a.tap_text()
        check(await a.visible("sentBar"), "asks 'Did your text go out?'")
        check(await a.txt("status") == "Waiting: did it send?", "status waiting")
        st = await a.state()
        check("sent" not in st["entries"]["2026-11-09"], "not marked sent yet")
        await a.pg.reload(); await a.pg.wait_for_function("()=>window.__hours")
        check(await a.visible("sentBar"), "question survives closing/reopening the app")
        await a.pg.click("#notSentBtn")
        check(not await a.visible("sentBar"), "Not sent dismisses")
        st = await a.state()
        check("sent" not in st["entries"]["2026-11-09"], "Not sent leaves the day unsent")
        await a.tap_text(); await a.pg.click("#sentBtn")
        check(await a.txt("status") == "✓ Sent", "Sent marks it")
        await a.shot("1-monday-sent")
        st = await a.state(); await a.close()

        print("Tuesday: clock-in draft, break placeholders, break outside shift")
        a = await App(p).open(2026, 11, 10, 9, 2, st)
        await a.pg.click("#startNow")
        check(await a.txt("status") == "Started 9:02am", "clock-in saved as draft")
        st = await a.state(); await a.close()
        a = await App(p).open(2026, 11, 10, 18, 17, st)
        check(await a.txt("status") == "Started 9:02am", "draft survives closing the app")
        await a.pg.click("#endNow")
        await a.pg.click("#addBrk")
        check(await a.disabled() and "placeholders" in await a.txt("warn"), "placeholder break blocks texting")
        await a.setb(0, "s", "12:10"); await a.setb(0, "e", "12:47")
        check(not await a.disabled(), "real break times unlock")
        await a.setb(0, "s", "19:00"); await a.setb(0, "e", "19:30")
        check(await a.disabled() and "inside your work hours" in await a.txt("warn"), "break outside the shift blocks")
        await a.setb(0, "s", "12:10"); await a.setb(0, "e", "12:47")
        await a.pg.click("#addBrk"); await a.setb(1, "s", "12:30"); await a.setb(1, "e", "12:40")
        check(await a.disabled() and "overlap" in await a.txt("warn"), "overlapping breaks block")
        await a.setb(1, "s", "15:00"); await a.setb(1, "e", "15:15")
        check(await a.txt("msg") == "11/10 9:02am-6:17pm (12:10pm-12:47pm, 3pm-3:15pm breaks) 8hrs 23min"
              + "\n18hrs 28min total for the week.", "two-break message")
        await a.tap_text(); await a.pg.click("#sentBtn")
        await a.shot("2-tuesday-breaks")

        print("Settings change doesn't cause false corrections")
        await a.pg.evaluate("()=>{const h=window.__hours; h.state.settings.showBrk=false; h.loadDate('2026-11-10');}")
        check(await a.txt("status") == "✓ Sent", "turning off break text keeps Tuesday as sent")
        check("●" not in await a.txt("weekList"), "no ● changed marks")
        await a.pg.evaluate("()=>{const h=window.__hours; h.state.settings.showBrk=true; h.loadDate('2026-11-10');}")

        print("Overnight shift asks for a one-tap confirm")
        await a.pg.evaluate("()=>window.__hours.loadDate('2026-11-12')")
        await a.set("start", "22:00"); await a.set("end", "02:30")
        check(await a.visible("ack") and await a.disabled(), "confirm shown, text held")
        await a.pg.click("#ackBtn")
        check(not await a.disabled(), "Yes, that's right unlocks")
        await a.pg.click("#delBtn"); await a.pg.click("#delBtn")   # clean up Thursday (never sent)
        check((await a.state())["entries"].get("2026-11-12") is None, "unsent day deletes outright")

        print("Deleting a sent day sends a correction, then clears")
        await a.pg.evaluate("()=>window.__hours.loadDate('2026-11-09')")
        await a.pg.click("#delBtn"); await a.pg.click("#delBtn")
        check(await a.visible("removedPanel"), "shows Removed")
        check(await a.txt("msg") == "Correction: 11/9 removed\n8hrs 23min total for the week.", "removal correction text")
        check("Removed" in await a.txt("weekList"), "week list shows the removal")
        await a.shot("3-removed")
        await a.tap_text(); await a.pg.click("#sentBtn")
        check((await a.state())["entries"].get("2026-11-09") is None, "removal record cleared once sent")

        print("Mark as not sent")
        await a.pg.evaluate("()=>window.__hours.loadDate('2026-11-10')")
        await a.pg.click("#unsendBtn")
        check(await a.txt("status") == "Logged · not sent", "unmarked")
        await a.pg.click("#toastUndo")
        check(await a.txt("status") == "✓ Sent", "undo restores")
        await a.close()

        print("Older saves load and migrate")
        old = {"entries": {
            "2026-11-09": {"start": "09:00", "end": "19:00", "brk": 0, "sent": {"line": "11/9 9am-7pm 10hrs", "total": "10hrs total for the week.", "at": 1}},
            "2026-11-10": {"start": "09:00", "end": "18:15", "brk": 0, "sent": {"line": "11/10 9am-6:15pm 9hrs 15min", "total": "19hrs 15min total for the week.", "at": 2}}},
            "settings": {"name": "", "phone": "1", "showBrk": True}}
        a = await App(p).open(2026, 11, 11, 18, 0, old)
        wl = await a.txt("weekList")
        check(wl.count("✓") == 2 and "●" not in wl, "both old sent days still count as sent")
        await a.set("start", "09:00"); await a.set("end", "17:00")
        check(await a.txt("msg") == "11/11 9am-5pm 8hrs 0min\n27hrs 15min total for the week.", "normal Wednesday text")
        await a.close()
        print("Travel day: clock in 4am, clock out 1am the next morning")
        base = {"entries": {}, "settings": {"name": "Mike", "phone": "9415550123", "showBrk": True}}
        a = await App(p).open(2026, 11, 10, 4, 0, base)
        await a.pg.click("#startNow")
        check(await a.txt("status") == "Started 4am", "clocked in at 4am")
        st = await a.state(); await a.close()
        a = await App(p).open(2026, 11, 11, 1, 0, st)               # reopened at 1am Wednesday
        check(await a.pg.evaluate("()=>window.__hours.cur") == "2026-11-10", "opens Tuesday, not Wednesday")
        check(await a.txt("status") == "Started 4am · not finished", "shows the open clock-in")
        check(await a.txt("endVal") == "1am", "end time defaults to now (1am)")
        await a.pg.click("#endNow")
        check(await a.visible("ack") and await a.disabled(), "past-midnight day asks for a confirm")
        check("21hrs 0min" in await a.txt("ackTxt"), "confirm shows 21hrs")
        await a.pg.click("#ackBtn")
        check(await a.txt("msg") == "11/10 4am-1am 21hrs 0min\n21hrs 0min total for the week.", "travel-day text")
        await a.tap_text(); await a.pg.click("#sentBtn")
        check(await a.txt("status") == "✓ Sent", "sent")
        await a.shot("6-travel-day")

        print("Next travel day starts 4am Wednesday: no overlap, totals add")
        await a.pg.evaluate("()=>window.__hours.loadDate('2026-11-11')")
        await a.set("start", "04:00"); await a.set("end", "01:00"); await a.pg.click("#ackBtn")
        check(await a.txt("msg") == "11/11 4am-1am 21hrs 0min\n42hrs 0min total for the week.", "second travel day adds to 42hrs")
        print("Overlap between days is blocked")
        await a.set("start", "00:30")                                 # Wed starting 12:30am overlaps Tue ending 1am
        check(await a.disabled() and "overlaps" in await a.txt("warn"), "overlap blocks texting")
        await a.shot("7-overlap")
        await a.close()

        print("Unfinished clock-in from yesterday stays put after noon")
        a = await App(p).open(2026, 11, 10, 4, 0, base)
        await a.pg.click("#startNow"); st = await a.state(); await a.close()
        a = await App(p).open(2026, 11, 11, 14, 0, st)
        check(await a.pg.evaluate("()=>window.__hours.cur") == "2026-11-11", "after noon, opens today")
        check("Started 4am" in await a.txt("weekList"), "yesterday's open clock-in still visible in the week")
        await a.close()

    print(f"\n{'ALL PASSED' if not failures else str(len(failures)) + ' FAILED'}")
    sys.exit(1 if failures else 0)

asyncio.run(main())
