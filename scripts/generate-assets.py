#!/usr/bin/env python3
"""TokenCat 커스텀 픽셀 아트 스프라이트 생성 (냥캣 오마주 — 전부 자체 제작).

18×11 논리 그리드 → 1셀=4px → 72×44px PNG (@2x, 로더가 36×22pt로 표시).
어두운 외곽선을 구워 넣어 라이트 메뉴바에서도 잘 보인다 (§F1).

사용: python3 scripts/generate-assets.py   → Sources/TokenCat/Assets/*.png
"""
from PIL import Image
from pathlib import Path

GRID_W, GRID_H, CELL = 18, 11, 4
OUT = Path(__file__).resolve().parent.parent / "Sources/TokenCat/Assets"

# 팔레트 (원작 냥캣 색을 그대로 쓰지 않은 자체 배색)
OUTLINE = (55, 55, 58, 255)
CRUST = (214, 150, 70, 255)       # 팝타르트 크러스트
FROSTING = (255, 140, 200, 255)   # 프로스팅
GRAY = (158, 158, 164, 255)       # 고양이 몸
EYE = (40, 40, 45, 255)
CHEEK = (255, 170, 190, 255)
SWEAT = (90, 170, 255, 255)
RED = (232, 64, 64, 255)
RED_OUTLINE = (150, 30, 30, 255)
ZZZ = (120, 120, 200, 255)
SPRINKLES = [(255, 90, 90, 255), (90, 190, 255, 255), (255, 220, 90, 255), (130, 220, 130, 255)]
RAINBOW = [(255, 70, 70, 255), (255, 160, 60, 255), (255, 225, 70, 255),
           (90, 205, 100, 255), (80, 150, 255, 255), (170, 100, 230, 255)]


class Sprite:
    """solid: 외곽선이 붙는 본체 / deco: 외곽선 없는 장식(트레일, Zzz, 땀, 느낌표)."""

    def __init__(self, outline=OUTLINE):
        self.solid, self.deco, self.outline_color = {}, {}, outline

    def rect(self, x, y, w, h, color, deco=False):
        layer = self.deco if deco else self.solid
        for cx in range(x, x + w):
            for cy in range(y, y + h):
                if 0 <= cx < GRID_W and 0 <= cy < GRID_H:
                    layer[(cx, cy)] = color

    def save(self, name):
        img = Image.new("RGBA", (GRID_W * CELL, GRID_H * CELL), (0, 0, 0, 0))
        cells = {}
        # 외곽선: solid에 4방향 인접한 빈 셀
        for (x, y) in self.solid:
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if 0 <= nx < GRID_W and 0 <= ny < GRID_H and (nx, ny) not in self.solid:
                    cells[(nx, ny)] = self.outline_color
        cells.update(self.deco)     # 장식은 외곽선 위, 본체 아래
        cells.update(self.solid)
        for (x, y), color in cells.items():
            for px in range(x * CELL, (x + 1) * CELL):
                for py in range(y * CELL, (y + 1) * CELL):
                    img.putpixel((px, py), color)
        img.save(OUT / f"{name}.png")


LEG_POSES = [(4, 14), (5, 13), (7, 11), (6, 12)]   # (뒷다리 x, 앞다리 x) — Swift 생성기와 동일
SPRINKLE_POS = [(6, 5), (8, 4), (10, 6), (11, 4), (7, 7), (9, 5)]


def draw_poptart_cat(s, bob=0, pose=0, legs=True):
    """팝타르트 몸통 + 고양이 머리/꼬리/다리 (오른쪽 진행)."""
    # 꼬리
    s.rect(2, 4 + bob, 2, 1, GRAY)
    s.rect(3, 3 + bob, 1, 1, GRAY)
    # 팝타르트: 크러스트 + 프로스팅 + 스프링클
    s.rect(4, 3 + bob, 10, 6, CRUST)
    s.rect(5, 4 + bob, 8, 4, FROSTING)
    for i, (sx, sy) in enumerate(SPRINKLE_POS):
        s.rect(sx, sy + bob, 1, 1, SPRINKLES[i % len(SPRINKLES)])
    # 머리 (몸 오른쪽에 겹침) + 귀
    s.rect(12, 2 + bob, 5, 4, GRAY)
    s.rect(12, 1 + bob, 1, 1, GRAY)
    s.rect(16, 1 + bob, 1, 1, GRAY)
    # 얼굴
    s.rect(13, 3 + bob, 1, 1, EYE)
    s.rect(15, 3 + bob, 1, 1, EYE)
    s.rect(12, 5 + bob, 1, 1, CHEEK)
    s.rect(16, 5 + bob, 1, 1, CHEEK)
    # 다리 (지면 고정 — 몸이 내려앉는 착지 포즈 연출)
    if legs:
        back, front = LEG_POSES[pose]
        s.rect(back, 9, 2, 2, GRAY)
        s.rect(front, 9, 2, 2, GRAY)


def run_frame(index, rainbow=False):
    pose = index % 4
    bob = 1 if pose == 2 else 0
    s = Sprite()
    if rainbow:
        wave = index % 2
        for i, color in enumerate(RAINBOW):
            s.rect(0, 2 + i + wave, 4 - wave, 1, color, deco=True)
    draw_poptart_cat(s, bob=bob, pose=pose)
    return s


def sleep_frame(index):
    s = Sprite()
    # 웅크린 회색 고양이 (팝타르트는 벗어둠)
    s.rect(5, 6, 9, 4, GRAY)
    s.rect(6, 5, 7, 1, GRAY)
    s.rect(11, 4, 4, 3, GRAY)           # 파묻힌 머리
    s.rect(11, 3, 1, 1, GRAY)           # 귀
    s.rect(14, 3, 1, 1, GRAY)
    s.rect(12, 5, 2, 1, EYE)            # 감은 눈
    s.rect(4, 8, 2, 2, GRAY)            # 감싼 꼬리
    if index == 0:
        s.rect(16, 2, 1, 1, ZZZ, deco=True)
    else:
        s.rect(16, 1, 1, 1, ZZZ, deco=True)
        s.rect(17, 3, 1, 1, ZZZ, deco=True)
    return s


def tired_frame(index):
    pant = index % 2
    s = Sprite()
    draw_poptart_cat(s, bob=pant, pose=2, legs=False)
    s.rect(5, 9, 2, 2, GRAY)            # 주저앉은 다리
    s.rect(12, 9, 2, 2, GRAY)
    if pant == 1:
        s.rect(14, 5 + pant, 1, 1, EYE)  # 헐떡이는 입
    s.rect(17, 1 + pant * 2, 1, 1, SWEAT, deco=True)   # 💧 낙하
    return s


def alert_frame(index):
    s = Sprite(outline=RED_OUTLINE)
    # 실루엣 전체 빨강 (정지 자세)
    s.rect(2, 4, 2, 1, RED)
    s.rect(3, 3, 1, 1, RED)
    s.rect(4, 3, 10, 6, RED)
    s.rect(12, 2, 5, 4, RED)
    s.rect(12, 1, 1, 1, RED)
    s.rect(16, 1, 1, 1, RED)
    s.rect(13, 3, 1, 1, EYE)
    s.rect(15, 3, 1, 1, EYE)
    s.rect(6, 9, 2, 2, RED)
    s.rect(12, 9, 2, 2, RED)
    if index == 0:                      # ❗ 깜빡임
        s.rect(0, 1, 1, 4, RED, deco=True)
        s.rect(0, 6, 1, 1, RED, deco=True)
    return s


def main():
    OUT.mkdir(exist_ok=True)
    for i in range(8):
        run_frame(i).save(f"cat_run_{i}")
        run_frame(i, rainbow=True).save(f"cat_rainbow_{i}")
    for i in range(2):
        sleep_frame(i).save(f"cat_sleep_{i}")
        tired_frame(i).save(f"cat_tired_{i}")
        alert_frame(i).save(f"cat_alert_{i}")
    print(f"✓ {len(list(OUT.glob('*.png')))}개 PNG 생성 → {OUT}")


if __name__ == "__main__":
    main()
