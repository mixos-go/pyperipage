"""
crop_editor.py

Screen "Crop Manual" -- jendela terpisah (Toplevel) untuk mengatur crop
per halaman secara manual, lalu (opsional) menjadikan pengaturan itu
sebagai POLA yang di-apply rata ke SEMUA halaman lain.

ATURAN POLA CROP (sesuai kesepakatan):
- Yang diatur manual HANYA offset ATAS dan BAWAH (dalam mm, ditampilkan
  juga dalam px) -- ini nilai TETAP (fixed) yang sama untuk semua halaman.
- Bagian TENGAH tidak diatur sama sekali -- otomatis mengikuti sisa
  panjang asli tiap halaman, jadi tetap benar walau panjang halaman
  beda-beda.
- Kiri/kanan tetap dipotong otomatis (whitespace detection) dan dikunci
  ke lebar kertas fisik yang aktif, sama seperti auto-crop biasa.

Alur pemakaian:
1. Pengguna klik "Crop Manual" di salah satu baris halaman -> jendela ini
   terbuka menampilkan halaman MENTAH (raw, sebelum crop) tsb.
2. Dua garis horizontal (atas & bawah) bisa digeser dengan mouse, atau
   diketik presisi lewat kolom mm di bawah.
3. "Simpan Halaman Ini" -> hanya berlaku utk halaman yang sedang dibuka.
4. "Terapkan ke SEMUA Halaman" -> nilai offset ini dijadikan pola global,
   di-broadcast & dihitung ulang ke seluruh halaman lain.
5. Preview di app utama (panel kanan) otomatis ter-refresh sesudahnya --
   jadi pengguna selalu bisa lihat hasil sebelum menekan tombol cetak.
"""
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk

from peripage_logic import (
    manual_crop_and_resize,
    auto_detect_full_bbox,
    mm_to_px,
    px_to_mm,
)

MAX_CANVAS_W = 380
MAX_CANVAS_H = 560
HANDLE_GRAB_PX = 10   # toleransi jarak klik utk "kena" garis mana


class CropEditorWindow:
    def __init__(self, root, app, page_index):
        self.app = app
        self.page_index = page_index
        self.raw_img = app.raw_pages[page_index]
        self.orig_w, self.orig_h = self.raw_img.size

        # Batas kanvas dihitung ulang berdasarkan resolusi layar yang
        # SEBENARNYA (bukan cuma konstanta tetap MAX_CANVAS_W/H). Kalau
        # tetap pakai konstanta tetap, di layar yang lebih pendek dari
        # (canvas + label + kontrol mm + tombol2) window ini akan lebih
        # tinggi daripada layar itu sendiri -- akibatnya tombol "Simpan
        # Halaman Ini" / "Terapkan ke SEMUA Halaman" di paling bawah bisa
        # jatuh keluar dari area layar dan tidak bisa diklik, terlepas
        # dari arah drag garis crop-nya.
        screen_w = root.winfo_screenwidth()
        screen_h = root.winfo_screenheight()
        # Perkiraan tinggi non-kanvas: label instruksi + 2 baris kontrol mm
        # + label hasil + baris tombol (Reset/Batal/Simpan) + tombol
        # "Terapkan ke Semua" + tombol "Salin ke Halaman Tertentu" + padding.
        reserved_chrome_h = 320
        reserved_margin_w = 120

        effective_max_h = max(200, min(MAX_CANVAS_H, screen_h - reserved_chrome_h))
        effective_max_w = max(240, min(MAX_CANVAS_W, screen_w - reserved_margin_w))

        self.scale = min(effective_max_w / self.orig_w, effective_max_h / self.orig_h, 1.0)
        self.canvas_w = int(self.orig_w * self.scale)
        self.canvas_h = int(self.orig_h * self.scale)

        # ---- Nilai awal (mm) ----
        # Prioritas: override khusus halaman ini > pola global (kalau mode
        # sudah manual) > tebakan dari auto-crop (biar titik awal masuk akal).
        if page_index in app.page_crop_overrides:
            top_mm, bottom_mm = app.page_crop_overrides[page_index]
        elif app.crop_mode == "manual":
            top_mm, bottom_mm = app.manual_top_mm, app.manual_bottom_mm
        else:
            _, auto_upper, _, auto_lower = auto_detect_full_bbox(self.raw_img)
            top_mm = round(px_to_mm(auto_upper), 1)
            bottom_mm = round(px_to_mm(self.orig_h - auto_lower), 1)

        self.top_mm_var = tk.DoubleVar(value=top_mm)
        self.bottom_mm_var = tk.DoubleVar(value=bottom_mm)
        self._suspend_trace = False

        self.dragging = None  # "top" | "bottom" | None

        self.top = tk.Toplevel(root)
        self.top.title(f"Crop Manual — Halaman {page_index + 1} / {app.total_pages}")
        self.top.resizable(False, False)
        self.top.transient(root)

        self._build_widgets()
        self._render_base_image()
        self._sync_lines_from_mm()
        self._redraw_overlay()
        self._position_window_on_screen()
        self.top.grab_set()

    def _position_window_on_screen(self):
        """Posisikan jendela Crop Editor supaya SELALU sepenuhnya berada
        di dalam batas layar yang terlihat -- dipusatkan relatif ke
        window utama kalau memungkinkan, tapi di-clamp supaya tidak
        pernah melewati tepi kanan/bawah layar. Ini yang memperbaiki bug
        window "turun ke bawah" sampai tombol Simpan/Terapkan-nya keluar
        dari jangkauan desktop dan tidak bisa diklik."""
        self.top.update_idletasks()
        win_w = self.top.winfo_reqwidth()
        win_h = self.top.winfo_reqheight()
        screen_w = self.top.winfo_screenwidth()
        screen_h = self.top.winfo_screenheight()

        try:
            root_x = self.top.master.winfo_x()
            root_y = self.top.master.winfo_y()
            root_w = self.top.master.winfo_width()
            root_h = self.top.master.winfo_height()
            x = root_x + (root_w - win_w) // 2
            y = root_y + (root_h - win_h) // 2
        except tk.TclError:
            x = (screen_w - win_w) // 2
            y = (screen_h - win_h) // 2

        # Clamp: paksa seluruh window (kiri/atas maupun kanan/bawah) tetap
        # berada di dalam area layar yang terlihat.
        x = max(0, min(x, screen_w - win_w))
        y = max(0, min(y, screen_h - win_h))

        self.top.geometry(f"{win_w}x{win_h}+{x}+{y}")

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------
    def _build_widgets(self):
        outer = ttk.Frame(self.top, padding=10)
        outer.pack(fill="both", expand=True)

        # ------------------------------------------------------------
        # SEMUA kontrol & tombol SENGAJA ditaruh DI ATAS dulu (posisi
        # tetap, di-pack sebelum area gambar). Gambar/canvas crop di
        # bagian paling bawah adalah satu-satunya bagian yang ukurannya
        # dihitung menyesuaikan sisa layar (lihat effective_max_h di
        # __init__) -- jadi kalau layar pendek, yang mengecil duluan
        # adalah gambar preview-nya, BUKAN tombol "Simpan"/"Terapkan ke
        # Semua"/"Salin ke Halaman Tertentu" yang jadi tidak kelihatan
        # atau tidak terjangkau seperti sebelumnya.
        # ------------------------------------------------------------
        ttk.Label(
            outer,
            text="Geser garis merah (atas & bawah) di gambar, atau ketik nilai mm.\n"
                 "Bagian tengah otomatis menyesuaikan panjang halaman ini.",
            justify="center", foreground="gray"
        ).pack(pady=(0, 8))

        # ---- Kontrol nilai presisi (mm) ----
        controls = ttk.Frame(outer, padding=(0, 4))
        controls.pack(fill="x")

        row_top = ttk.Frame(controls)
        row_top.pack(fill="x", pady=2)
        ttk.Label(row_top, text="Offset atas (mm):", width=16).pack(side="left")
        self.spin_top = ttk.Spinbox(row_top, from_=0, to=500, increment=0.5, width=8,
                                     textvariable=self.top_mm_var, command=self._on_spin_change)
        self.spin_top.pack(side="left")
        self.spin_top.bind("<Return>", lambda e: self._on_spin_change())
        self.spin_top.bind("<FocusOut>", lambda e: self._on_spin_change())
        self.lbl_top_px = ttk.Label(row_top, text="", foreground="gray")
        self.lbl_top_px.pack(side="left", padx=8)

        row_bottom = ttk.Frame(controls)
        row_bottom.pack(fill="x", pady=2)
        ttk.Label(row_bottom, text="Offset bawah (mm):", width=16).pack(side="left")
        self.spin_bottom = ttk.Spinbox(row_bottom, from_=0, to=500, increment=0.5, width=8,
                                        textvariable=self.bottom_mm_var, command=self._on_spin_change)
        self.spin_bottom.pack(side="left")
        self.spin_bottom.bind("<Return>", lambda e: self._on_spin_change())
        self.spin_bottom.bind("<FocusOut>", lambda e: self._on_spin_change())
        self.lbl_bottom_px = ttk.Label(row_bottom, text="", foreground="gray")
        self.lbl_bottom_px.pack(side="left", padx=8)

        self.lbl_result = ttk.Label(controls, text="", foreground="#0a6")
        self.lbl_result.pack(anchor="w", pady=(6, 4))

        # ---- Tombol aksi (semua di atas, sebelum gambar) ----
        btns = ttk.Frame(outer, padding=(0, 4))
        btns.pack(fill="x")
        ttk.Button(btns, text="Reset (Auto-Crop)", command=self._on_reset_auto).pack(side="left")
        ttk.Button(btns, text="Batal", command=self.top.destroy).pack(side="right", padx=(6, 0))
        ttk.Button(btns, text="Simpan Halaman Ini", command=self._on_save_this_page).pack(side="right", padx=(6, 0))

        ttk.Button(
            outer, text="✓ Terapkan Pola Ini ke SEMUA Halaman",
            command=self._on_apply_all
        ).pack(fill="x", ipady=6, pady=(4, 0))

        ttk.Button(
            outer, text="→ Salin Pola Ini ke Halaman Tertentu...",
            command=self._on_copy_to_specific_pages
        ).pack(fill="x", ipady=6, pady=(4, 4))

        # ---- Gambar / canvas crop -- di BAWAH, bagian yang boleh menyusut ----
        canvas_frame = ttk.Frame(outer, relief="sunken", borderwidth=1)
        canvas_frame.pack()
        self.canvas = tk.Canvas(canvas_frame, width=self.canvas_w, height=self.canvas_h,
                                 bg="#DDDDDD", highlightthickness=0, cursor="sb_v_double_arrow")
        self.canvas.pack()
        self.canvas.bind("<Button-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)

    def _render_base_image(self):
        display_img = self.raw_img.copy().resize(
            (self.canvas_w, self.canvas_h), Image.Resampling.NEAREST
        )
        self.tk_base_img = ImageTk.PhotoImage(display_img)
        self.canvas.create_image(0, 0, anchor="nw", image=self.tk_base_img, tags=("base",))

    # ------------------------------------------------------------------
    # Konversi mm (nilai asli, di-clamp) <-> posisi y di canvas (scaled)
    # ------------------------------------------------------------------
    def _mm_to_canvas_y_top(self, mm):
        px = mm_to_px(mm)
        return px * self.scale

    def _mm_to_canvas_y_bottom(self, mm):
        px = mm_to_px(mm)
        return self.canvas_h - (px * self.scale)

    def _canvas_y_to_top_mm(self, y):
        px = y / self.scale
        return round(px_to_mm(px), 1)

    def _canvas_y_to_bottom_mm(self, y):
        px = (self.canvas_h - y) / self.scale
        return round(px_to_mm(px), 1)

    def _sync_lines_from_mm(self):
        min_gap = 16
        self.top_line_y = max(0, min(self._mm_to_canvas_y_top(self.top_mm_var.get()), self.canvas_h - min_gap))
        self.bottom_line_y = min(self.canvas_h, max(self._mm_to_canvas_y_bottom(self.bottom_mm_var.get()), self.top_line_y + min_gap))

    # ------------------------------------------------------------------
    # Interaksi drag
    # ------------------------------------------------------------------
    def _on_press(self, event):
        d_top = abs(event.y - self.top_line_y)
        d_bottom = abs(event.y - self.bottom_line_y)
        if min(d_top, d_bottom) > HANDLE_GRAB_PX:
            self.dragging = None
            return
        self.dragging = "top" if d_top <= d_bottom else "bottom"

    def _on_drag(self, event):
        if not self.dragging:
            return
        min_gap = 16
        y = max(0, min(event.y, self.canvas_h))
        if self.dragging == "top":
            self.top_line_y = min(y, self.bottom_line_y - min_gap)
            self.top_line_y = max(0, self.top_line_y)
        else:
            self.bottom_line_y = max(y, self.top_line_y + min_gap)
            self.bottom_line_y = min(self.canvas_h, self.bottom_line_y)

        self._suspend_trace = True
        self.top_mm_var.set(self._canvas_y_to_top_mm(self.top_line_y))
        self.bottom_mm_var.set(self._canvas_y_to_bottom_mm(self.bottom_line_y))
        self._suspend_trace = False
        self._redraw_overlay()

    def _on_release(self, event):
        self.dragging = None

    def _on_spin_change(self):
        if self._suspend_trace:
            return
        try:
            self.top_mm_var.get()
            self.bottom_mm_var.get()
        except tk.TclError:
            return
        self._sync_lines_from_mm()
        self._redraw_overlay()

    # ------------------------------------------------------------------
    # Render overlay (garis + area yang akan dibuang, digelapkan)
    # ------------------------------------------------------------------
    def _redraw_overlay(self):
        self.canvas.delete("overlay")

        # Area terbuang (redup)
        if self.top_line_y > 0:
            self.canvas.create_rectangle(0, 0, self.canvas_w, self.top_line_y,
                                          fill="black", stipple="gray50", outline="",
                                          tags=("overlay",))
        if self.bottom_line_y < self.canvas_h:
            self.canvas.create_rectangle(0, self.bottom_line_y, self.canvas_w, self.canvas_h,
                                          fill="black", stipple="gray50", outline="",
                                          tags=("overlay",))

        # Garis + handle
        self.canvas.create_line(0, self.top_line_y, self.canvas_w, self.top_line_y,
                                 fill="#ff3b30", width=2, tags=("overlay",))
        self.canvas.create_rectangle(0, self.top_line_y - 5, 14, self.top_line_y + 5,
                                      fill="#ff3b30", outline="", tags=("overlay",))

        self.canvas.create_line(0, self.bottom_line_y, self.canvas_w, self.bottom_line_y,
                                 fill="#ff3b30", width=2, tags=("overlay",))
        self.canvas.create_rectangle(0, self.bottom_line_y - 5, 14, self.bottom_line_y + 5,
                                      fill="#ff3b30", outline="", tags=("overlay",))

        top_px = mm_to_px(self.top_mm_var.get())
        bottom_px = mm_to_px(self.bottom_mm_var.get())
        sisa_px = max(0, self.orig_h - top_px - bottom_px)
        self.lbl_top_px.config(text=f"({top_px} px)")
        self.lbl_bottom_px.config(text=f"({bottom_px} px)")
        self.lbl_result.config(
            text=f"Tinggi halaman asli: {self.orig_h}px  →  sisa konten tengah: {sisa_px}px "
                 f"({round(px_to_mm(sisa_px), 1)}mm) — otomatis menyesuaikan per halaman."
        )

    # ------------------------------------------------------------------
    # Aksi
    # ------------------------------------------------------------------
    def _current_offsets_px(self):
        return mm_to_px(self.top_mm_var.get()), mm_to_px(self.bottom_mm_var.get())

    def _on_reset_auto(self):
        _, auto_upper, _, auto_lower = auto_detect_full_bbox(self.raw_img)
        self._suspend_trace = True
        self.top_mm_var.set(round(px_to_mm(auto_upper), 1))
        self.bottom_mm_var.set(round(px_to_mm(self.orig_h - auto_lower), 1))
        self._suspend_trace = False
        self._sync_lines_from_mm()
        self._redraw_overlay()

    def _on_save_this_page(self):
        top_px, bottom_px = self._current_offsets_px()
        top_mm, bottom_mm = self.top_mm_var.get(), self.bottom_mm_var.get()
        self.app.page_crop_overrides[self.page_index] = (top_mm, bottom_mm)
        self.app.cropped_pages_images[self.page_index] = manual_crop_and_resize(
            self.raw_img, top_px, bottom_px, paper_width_mm=self.app.paper_width_mm
        )
        self.app.on_crop_editor_saved(self.page_index)
        self.top.destroy()

    def _on_apply_all(self):
        top_mm, bottom_mm = self.top_mm_var.get(), self.bottom_mm_var.get()
        self.app.apply_manual_crop_pattern_to_all(top_mm, bottom_mm)
        self.top.destroy()

    def _on_copy_to_specific_pages(self):
        """Buka dialog kecil berisi checkbox semua halaman LAIN (selain
        halaman yang sedang dibuka), lalu salin offset atas/bawah yang
        sedang aktif di editor ini sebagai OVERRIDE khusus ke tiap halaman
        yang dicentang -- tanpa mengubah halaman lain yang tidak dipilih
        dan tanpa mengubah mode crop global. Ini melengkapi 'Terapkan ke
        SEMUA Halaman' utk kasus saat pengguna cuma mau menyalin pola ke
        satu/dua halaman tertentu saja, bukan seluruh dokumen."""
        top_mm, bottom_mm = self.top_mm_var.get(), self.bottom_mm_var.get()
        other_indices = [i for i in range(len(self.app.raw_pages)) if i != self.page_index]
        if not other_indices:
            from tkinter import messagebox
            messagebox.showinfo("Info", "Tidak ada halaman lain untuk disalin polanya.")
            return

        picker = tk.Toplevel(self.top)
        picker.title("Pilih Halaman Tujuan")
        picker.transient(self.top)

        ttk.Label(
            picker,
            text=f"Salin pola crop ({top_mm}mm atas / {bottom_mm}mm bawah)\nke halaman mana saja?",
            justify="center", padding=10
        ).pack()

        list_frame = ttk.Frame(picker, padding=(10, 0))
        list_frame.pack(fill="both", expand=True)

        check_vars = {}
        for idx in other_indices:
            var = tk.BooleanVar(value=False)
            check_vars[idx] = var
            ttk.Checkbutton(list_frame, text=f"Halaman {idx + 1}", variable=var).pack(anchor="w")

        def select_all_targets():
            for v in check_vars.values():
                v.set(True)

        def do_copy():
            selected = [idx for idx, v in check_vars.items() if v.get()]
            if not selected:
                from tkinter import messagebox
                messagebox.showwarning("Peringatan", "Pilih minimal satu halaman tujuan.")
                return
            for idx in selected:
                self.app.page_crop_overrides[idx] = (top_mm, bottom_mm)
                self.app.cropped_pages_images[idx] = manual_crop_and_resize(
                    self.app.raw_pages[idx], mm_to_px(top_mm), mm_to_px(bottom_mm),
                    paper_width_mm=self.app.paper_width_mm
                )
                self.app.on_crop_editor_saved(idx)
            self.app.root.update_idletasks()
            picker.destroy()
            self.top.destroy()

        btns = ttk.Frame(picker, padding=10)
        btns.pack(fill="x")
        ttk.Button(btns, text="Pilih Semua", command=select_all_targets).pack(side="left")
        ttk.Button(btns, text="Batal", command=picker.destroy).pack(side="right", padx=(6, 0))
        ttk.Button(btns, text="Salin", command=do_copy).pack(side="right", padx=(6, 0))

        picker.update_idletasks()
        # Clamp posisi picker ke layar juga, konsisten dengan window utamanya.
        screen_w = picker.winfo_screenwidth()
        screen_h = picker.winfo_screenheight()
        win_w = picker.winfo_reqwidth()
        win_h = picker.winfo_reqheight()
        x = self.top.winfo_x() + 30
        y = self.top.winfo_y() + 30
        x = max(0, min(x, screen_w - win_w))
        y = max(0, min(y, screen_h - win_h))
        picker.geometry(f"{win_w}x{win_h}+{x}+{y}")
        picker.grab_set()
