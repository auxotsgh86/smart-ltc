# 重新產生 README 用的原型截圖：pip install playwright && playwright install chromium && python scripts/screenshots.py
from playwright.sync_api import sync_playwright
import pathlib
ROOT=pathlib.Path(__file__).resolve().parent.parent
R=(ROOT/'prototypes').as_uri()+'/'
O=str(ROOT/'docs'/'screenshots')+'/'
with sync_playwright() as p:
    b=p.chromium.launch()
    errs=[]
    # pharmacy counter (desktop)
    pg=b.new_page(viewport={'width':1100,'height':760},device_scale_factor=1.5)
    pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.goto(R+'pharmacy-counter.html');pg.wait_for_timeout(600)
    pg.screenshot(path=O+'counter-1-checkin.png')
    pg.click('[data-act=card]');pg.wait_for_timeout(1500)
    pg.click('[data-act=recv]');pg.wait_for_timeout(1400)
    pg.screenshot(path=O+'counter-2-measure.png')
    pg.click('[data-act=ok]')
    pg.click('[data-act=recv]');pg.wait_for_timeout(1400);pg.click('[data-act=ok]')
    pg.click('[data-act=recv]');pg.wait_for_timeout(1400);pg.click('[data-act=ok]')
    pg.click('[data-act=skip]');pg.wait_for_timeout(3200)
    pg.screenshot(path=O+'counter-3-result.png',full_page=True)
    pg.click('[data-nav=care]');pg.wait_for_timeout(300)
    pg.screenshot(path=O+'counter-4-care.png')
    # patient phone
    pg=b.new_page(viewport={'width':390,'height':844},device_scale_factor=2)
    pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.goto(R+'patient-phone.html');pg.wait_for_timeout(600)
    pg.screenshot(path=O+'phone-1-home.png')
    pg.click('[data-act=keypad]')
    for d in '142':pg.click(f'[data-d="{d}"]')
    pg.screenshot(path=O+'phone-2-keypad.png')
    pg.click('[data-d=ok]')
    for d in '88':pg.click(f'[data-d="{d}"]')
    pg.click('[data-d=ok]');pg.click('[data-act=yes]');pg.wait_for_timeout(200)
    pg.click('[data-act=r2]');pg.click('[data-act=keypad]')
    for d in '136':pg.click(f'[data-d="{d}"]')
    pg.click('[data-d=ok]')
    for d in '84':pg.click(f'[data-d="{d}"]')
    pg.click('[data-d=ok]');pg.click('[data-act=yes]');pg.wait_for_timeout(300)
    pg.screenshot(path=O+'phone-3-result.png')
    pg.click('#tabs [data-t=trend]');pg.wait_for_timeout(400)
    pg.screenshot(path=O+'phone-4-trend.png')
    print(errs)
