import os
import tkinter as tk
import traceback
from tkinter import filedialog, messagebox, ttk
from PIL import Image, ImageChops, ImageTk
from pdf2image import convert_from_path
from peripage_logic import (
    smart_crop_and_resize, manual_crop_and_resize, execute_printing,
    load_paper_width_mm, save_paper_width_mm, SUPPORTED_PAPER_WIDTHS_MM, mm_to_px
)
from crop_editor import CropEditorWindow
from app_updater import (
    get_app_dir, is_git_repo, read_local_version,
    git_pull, extract_zip_to_temp, apply_package_update
)

class PeriPageApp:
    def __init__(self, root):
        self.root = root
        self.root.title("PeriPage A9 - PDF Smart Printer & Preview")
        self._configure_window_geometry()

        self.printer_connected = False
        self.pdf_path = ""
        self.raw_pages = []              # Halaman mentah hasil render PDF/gambar (belum di-crop), disimpan agar bisa direproses saat ganti kertas
        self.cropped_pages_images = {}   
        self.selected_pages = {}         
        self.current_preview_idx = 0
        self.total_pages = 0
        self.row_crop_labels = {}        # idx -> label widget "(Auto)"/"(Manual)" di daftar halaman

        # --- State Crop Manual ---
        # crop_mode "auto"   : semua halaman pakai smart_crop_and_resize (whitespace detection 4-arah)
        # crop_mode "manual" : semua halaman (kecuali yang di-override) pakai pola offset atas/bawah tetap
        self.crop_mode = "auto"
        self.manual_top_mm = 0.0
        self.manual_bottom_mm = 0.0
        self.page_crop_overrides = {}    # idx -> (top_mm, bottom_mm) khusus halaman itu saja

        # Otomatis muat setting lebar kertas terakhir yang tersimpan
        self.paper_width_mm = load_paper_width_mm()

        self.initial_dir = os.path.expanduser("~/Downloads")
        if not os.path.exists(self.initial_dir):
            self.initial_dir = os.path.expanduser("~")

        self.create_widgets()

    def _configure_window_geometry(self):
        """Hitung ukuran & posisi window utama berdasarkan resolusi layar
        yang sebenarnya, supaya window (dan tombol2 di bagian bawahnya,
        misalnya tombol CETAK) TIDAK PERNAH keluar dari jangkauan desktop.

        Sebelumnya window dipaksa fixed 850x680 tanpa cek layar -- kalau
        area kerja layar pengguna lebih kecil dari itu, bagian bawah
        window (termasuk tombol Cetak) jatuh di luar layar dan tidak bisa
        diklik sama sekali. Sekarang window di-cap ke ukuran layar yang
        tersedia, dipusatkan, dan dibuat resizable + diberi minsize supaya
        pengguna tetap bisa menyesuaikan sendiri kalau perlu."""
        self.root.update_idletasks()
        target_w, target_h = 850, 680

        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()

        # Sisakan ruang utk taskbar/decorasi window (perkiraan aman)
        max_w = max(600, screen_w - 60)
        max_h = max(480, screen_h - 90)

        w = min(target_w, max_w)
        h = min(target_h, max_h)

        x = max(0, (screen_w - w) // 2)
        y = max(0, (screen_h - h) // 2)

        self.root.geometry(f"{w}x{h}+{x}+{y}")
        self.root.minsize(700, 480)
        # Resizable supaya kalau layar pengguna kecil/berubah, window bisa
        # di-maximize / ditarik sendiri dan tombol di bawah tetap terjangkau.
        self.root.resizable(True, True)

    def create_widgets(self):
        main_frame = ttk.Frame(self.root, padding=10)
        main_frame.pack(fill="both", expand=True)

        left_panel = ttk.Frame(main_frame)
        left_panel.pack(side="left", fill="both", expand=True, padx=(0, 10))
        self.left_panel = left_panel

        right_panel = ttk.LabelFrame(main_frame, text=" Live Preview (What You See Is What You Print) ", padding=10, width=340)
        right_panel.pack(side="right", fill="both")

        # 0. Bar versi & Cek Pembaruan -- SENGAJA paling atas & posisi tetap
        # (bukan expand), supaya selalu kelihatan tanpa perlu scroll dan
        # tidak pernah terpotong berapa pun tinggi window-nya.
        update_bar = ttk.Frame(left_panel, padding=(0, 0, 0, 8))
        update_bar.pack(fill="x")
        self.lbl_version = ttk.Label(
            update_bar, text=f"PeriPage A9 GUI  •  v{read_local_version()}",
            foreground="gray"
        )
        self.lbl_version.pack(side="left")
        self.btn_check_update = ttk.Button(
            update_bar, text="🔄 Cek Pembaruan...", command=self.check_for_updates
        )
        self.btn_check_update.pack(side="right")

        # 1. Status Printer
        conn_frame = ttk.LabelFrame(left_panel, text=" 1. Status Printer ", padding=10)
        conn_frame.pack(fill="x", pady=(0, 10))
        ttk.Button(conn_frame, text="Cek USB", command=self.check_printer_connection).pack(side="left", padx=5)
        self.lbl_conn_status = ttk.Label(conn_frame, text="Memeriksa...", font=("Helvetica", 10, "bold"), foreground="orange")
        self.lbl_conn_status.pack(side="left", padx=10)

        # 2. Pengaturan Kertas
        paper_frame = ttk.LabelFrame(left_panel, text=" 2. Lebar Roll Kertas ", padding=10)
        paper_frame.pack(fill="x", pady=5)
        ttk.Label(paper_frame, text="Kertas terpasang:").pack(side="left", padx=(0, 8))
        self.paper_width_var = tk.StringVar(value=f"{self.paper_width_mm}mm")
        self.cmb_paper_width = ttk.Combobox(
            paper_frame, textvariable=self.paper_width_var,
            values=[f"{w}mm" for w in SUPPORTED_PAPER_WIDTHS_MM],
            state="readonly", width=8
        )
        self.cmb_paper_width.pack(side="left")
        self.cmb_paper_width.bind("<<ComboboxSelected>>", self.on_paper_width_changed)
        self.lbl_paper_hint = ttk.Label(paper_frame, text="", foreground="gray")
        self.lbl_paper_hint.pack(side="left", padx=10)

        # 3. Mode Crop
        crop_mode_frame = ttk.LabelFrame(left_panel, text=" 3. Mode Crop ", padding=10)
        crop_mode_frame.pack(fill="x", pady=5)
        self.crop_mode_var = tk.StringVar(value="auto")
        ttk.Radiobutton(
            crop_mode_frame, text="Otomatis (Smart Crop)", value="auto",
            variable=self.crop_mode_var, command=self.on_crop_mode_changed
        ).pack(side="left", padx=5)
        ttk.Radiobutton(
            crop_mode_frame, text="Manual (Pola Tetap)", value="manual",
            variable=self.crop_mode_var, command=self.on_crop_mode_changed
        ).pack(side="left", padx=5)
        self.btn_edit_pattern = ttk.Button(
            crop_mode_frame, text="Atur Pola Crop...", command=self.open_crop_editor_for_current, state="disabled"
        )
        self.btn_edit_pattern.pack(side="left", padx=10)

        # 4. Pilih PDF
        self.file_frame = ttk.LabelFrame(left_panel, text=" 4. Pilih Dokumen PDF / Gambar ", padding=10)
        self.file_frame.pack(fill="x", pady=5)
        self.btn_browse = ttk.Button(self.file_frame, text="Buka PDF (Baru)", command=self.load_pdf, state="disabled")
        self.btn_browse.pack(side="left", padx=5)
        self.btn_import_images = ttk.Button(self.file_frame, text="Tambah PDF/Gambar (+)", command=self.import_files, state="disabled")
        self.btn_import_images.pack(side="left", padx=5)
        self.lbl_file_status = ttk.Label(self.file_frame, text="Hubungkan printer dulu", wraplength=260, foreground="gray")
        self.lbl_file_status.pack(side="left", padx=10)

        # Tombol Kendali & Cetak -- SENGAJA ditaruh DI ATAS (sesudah bagian 4,
        # SEBELUM daftar halaman), bukan di bawah. Daftar halaman di bagian 5
        # bisa jadi sangat panjang dan window ini tidak resizable penuh --
        # kalau tombol Cetak ditaruh di bawah daftar, ia gampang terpotong di
        # layar yang lebih pendek dari total tinggi kontennya. Dengan
        # ditaruh di sini (posisi tetap, tidak tergantung isi daftar di
        # bawahnya), tombol Cetak/Pilih Semua/Kosongkan SELALU kelihatan
        # penuh berapa pun tinggi window-nya -- yang menyusut kalau ruang
        # terbatas hanya daftar halaman (dan itu sudah ada scrollbar-nya).
        self.bulk_frame = ttk.Frame(left_panel, padding=5)
        self.bulk_frame.pack(fill="x", pady=5)
        self.btn_select_all = ttk.Button(self.bulk_frame, text="Pilih Semua", command=self.select_all, state="disabled")
        self.btn_select_all.pack(side="left", padx=5)
        self.btn_deselect_all = ttk.Button(self.bulk_frame, text="Kosongkan", command=self.deselect_all, state="disabled")
        self.btn_deselect_all.pack(side="left", padx=5)

        self.btn_print = ttk.Button(left_panel, text="CETAK HALAMAN TERPILIH", command=self.print_selected, state="disabled")
        self.btn_print.pack(fill="x", ipady=10, pady=5)

        # 5. Daftar Halaman
        self.page_frame = ttk.LabelFrame(left_panel, text=" 5. Daftar Halaman ", padding=10)
        self.page_frame.pack(fill="both", expand=True, pady=5)

        self.canvas = tk.Canvas(self.page_frame, borderwidth=0, highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(self.page_frame, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = ttk.Frame(self.canvas)
        self.scrollable_frame.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")

        # PANEL PREVIEW KANAN & NAVIGASI MULTI-PAGE
        self.preview_canvas = tk.Canvas(right_panel, bg="#EAEAEA", highlightthickness=1)
        self.preview_canvas.pack(fill="both", expand=True)
        
        # Navigasi halaman otomatis di bawah preview
        nav_frame = ttk.Frame(right_panel, padding=5)
        nav_frame.pack(fill="x", pady=5)
        self.btn_prev = ttk.Button(nav_frame, text="◀ Seb", command=self.prev_page, state="disabled")
        self.btn_prev.pack(side="left", expand=True)
        self.lbl_page_num = ttk.Label(nav_frame, text="0 / 0", font=("Helvetica", 10, "bold"))
        self.lbl_page_num.pack(side="left", padx=10)
        self.btn_next = ttk.Button(nav_frame, text="Sel ▶", command=self.next_page, state="disabled")
        self.btn_next.pack(side="left", expand=True)

        self.lbl_preview_info = ttk.Label(right_panel, text="Pilih halaman untuk preview", font=("Helvetica", 9), anchor="center")
        self.lbl_preview_info.pack(fill="x", pady=(2, 0))

        self.update_paper_hint()
        self.root.after(500, self.check_printer_connection)
        self._apply_real_minsize()

    def _apply_real_minsize(self):
        """Hitung ulang minsize window berdasarkan kebutuhan RIIL konten
        (bukan angka tebakan) supaya btn_print/bulk_frame TIDAK PERNAH
        terpotong. Hanya area '5. Daftar Halaman' (yang punya scrollbar
        sendiri) yang boleh diperkecil di bawah kebutuhan aslinya --
        semua elemen fix lain (status printer, kertas, mode crop, file,
        tombol bulk, tombol cetak) harus selalu punya ruang penuh."""
        self.root.update_idletasks()
        # Biarkan page_frame diperkecil ke tinggi minimal simbolis saat
        # menghitung total, supaya angka minsize tidak ikut membengkak
        # gara2 daftar halaman yang bisa jadi sangat panjang.
        fixed_children_h = 0
        for child in self.left_panel.winfo_children():
            if child is self.page_frame:
                fixed_children_h += 120  # tinggi minimal simbolis utk area scrollable
            else:
                fixed_children_h += child.winfo_reqheight()
        # + padding kasar antar section & border main_frame
        min_h = fixed_children_h + 80
        min_w = 700
        req_w = self.root.winfo_reqwidth()
        self.root.minsize(max(min_w, min(req_w, 900)), min_h)

    def check_for_updates(self):
        """Dipanggil oleh tombol '🔄 Cek Pembaruan...'. Ada 2 mode:
        - Kalau folder aplikasi ini adalah git repo -> tarik update via
          `git pull` dari remote yang sudah dikonfigurasi.
        - Kalau bukan -> minta pengguna pilih file .zip paket update
          (mis. hasil download source code terbaru dari developer)."""
        app_dir = get_app_dir()
        if is_git_repo(app_dir):
            if not messagebox.askyesno(
                "Cek Pembaruan",
                "Aplikasi ini terpasang sebagai git repository.\n\n"
                "Tarik pembaruan terbaru dari remote sekarang?"
            ):
                return
            self.btn_check_update.config(state="disabled", text="Memeriksa...")
            self.root.update_idletasks()
            try:
                ok, msg = git_pull(app_dir)
            finally:
                self.btn_check_update.config(state="normal", text="🔄 Cek Pembaruan...")
            if ok:
                messagebox.showinfo(
                    "Update Berhasil",
                    msg + "\n\nTutup dan buka ulang aplikasi ini supaya perubahan berlaku."
                )
            else:
                messagebox.showwarning("Cek Pembaruan", msg)
        else:
            self.open_package_update_dialog()

    def open_package_update_dialog(self):
        """Mode fallback tanpa git: pengguna pilih file .zip paket update
        (source code baru), lalu semua berkas kode disalin menimpa folder
        aplikasi ini (pengaturan pengguna di ~/.pyperipage tidak tersentuh)."""
        proceed = messagebox.askyesno(
            "Cek Pembaruan",
            "Aplikasi ini tidak terpasang sebagai git repository, jadi "
            "pembaruan dilakukan lewat 'paket update' (file .zip source "
            "code terbaru dari developer).\n\n"
            "Sudah punya file paket update (.zip) sekarang?"
        )
        if not proceed:
            return

        zip_path = filedialog.askopenfilename(
            title="Pilih Paket Update (.zip)",
            filetypes=[("Paket ZIP", "*.zip"), ("Semua File", "*.*")]
        )
        if not zip_path:
            return

        self.btn_check_update.config(state="disabled", text="Mengupdate...")
        self.root.update_idletasks()
        try:
            source_dir = extract_zip_to_temp(zip_path)
            ok, msg = apply_package_update(source_dir, get_app_dir())
        except Exception:
            traceback.print_exc()
            ok, msg = False, "Gagal memproses paket update. Pastikan file .zip valid."
        finally:
            self.btn_check_update.config(state="normal", text="🔄 Cek Pembaruan...")

        if ok:
            messagebox.showinfo(
                "Update Berhasil",
                msg + "\n\nTutup dan buka ulang aplikasi ini supaya perubahan berlaku."
            )
        else:
            messagebox.showerror("Update Gagal", msg)

    def check_printer_connection(self):
        self.lbl_conn_status.config(text="Memindai USB...", foreground="orange")
        self.root.update_idletasks()
        try:
            import usb.core
            from peripage_logic import force_detach_kernel
            dev = force_detach_kernel()
            if dev is not None:
                self.printer_connected = True
                self.lbl_conn_status.config(text="TERHUBUNG (USB)", foreground="green")
                self.btn_browse.config(state="normal")
                self.btn_import_images.config(state="normal")
                if not self.pdf_path: self.lbl_file_status.config(text="Printer siap. Silakan pilih PDF atau impor gambar.", foreground="black")
            else: raise Exception("Device not found")
        except Exception:
            self.printer_connected = False
            self.lbl_conn_status.config(text="TIDAK TERDETEKSI", foreground="red")
            self.btn_browse.config(state="disabled")
            self.btn_import_images.config(state="disabled")
            self.lbl_file_status.config(text="Hubungkan kabel USB & nyalakan printer.", foreground="gray")

    def update_paper_hint(self):
        px = self.paper_width_mm * 8
        self.lbl_paper_hint.config(text=f"({px}px per baris)")

    def on_paper_width_changed(self, event=None):
        """Dipanggil saat pengguna ganti pilihan lebar kertas di dropdown.
        Otomatis disimpan sebagai default & seluruh halaman yang sudah
        dimuat di-reproses ulang (re-crop) sesuai lebar baru, tanpa perlu
        buka ulang file PDF."""
        new_width = int(self.paper_width_var.get().replace("mm", ""))
        if new_width == self.paper_width_mm:
            return
        self.paper_width_mm = new_width
        save_paper_width_mm(new_width)
        self.update_paper_hint()

        if self.raw_pages:
            self.lbl_file_status.config(text=f"Menyesuaikan ulang halaman ke kertas {new_width}mm...", foreground="blue")
            self.root.update_idletasks()
            for i, raw_page in enumerate(self.raw_pages):
                self.cropped_pages_images[i] = self.smart_crop_and_resize_gui(i, raw_page)
            self.lbl_file_status.config(text=f"{os.path.basename(self.pdf_path)} ({self.total_pages} Hal) — kertas {new_width}mm", foreground="green")
            self.update_preview_display(self.current_preview_idx)

    def smart_crop_and_resize_gui(self, index, pil_img):
        """Router crop per halaman: pakai crop manual (override khusus halaman
        atau pola global) kalau ada, kalau tidak jatuh balik ke auto-crop
        (whitespace detection 4-arah) seperti biasa."""
        if index in self.page_crop_overrides:
            top_mm, bottom_mm = self.page_crop_overrides[index]
            return manual_crop_and_resize(
                pil_img, mm_to_px(top_mm), mm_to_px(bottom_mm), paper_width_mm=self.paper_width_mm
            )
        if self.crop_mode == "manual":
            return manual_crop_and_resize(
                pil_img, mm_to_px(self.manual_top_mm), mm_to_px(self.manual_bottom_mm),
                paper_width_mm=self.paper_width_mm
            )
        return smart_crop_and_resize(pil_img, paper_width_mm=self.paper_width_mm)

    def load_pdf(self):
        file_path = filedialog.askopenfilename(initialdir=self.initial_dir, filetypes=[("PDF Files", "*.pdf")])
        if not file_path: return
        self.pdf_path = file_path
        self.lbl_file_status.config(text="Sedang memproses PDF & Smart Crop...", foreground="blue")
        
        for w in self.scrollable_frame.winfo_children(): w.destroy()
        self.selected_pages.clear()
        self.cropped_pages_images.clear()
        self.row_crop_labels.clear()
        self.page_crop_overrides.clear()
        self.crop_mode = "auto"
        self.crop_mode_var.set("auto")
        self.manual_top_mm = 0.0
        self.manual_bottom_mm = 0.0
        self.raw_pages = []
        self.clear_preview()

        try:
            self.root.update_idletasks()
            raw_pages = convert_from_path(file_path, dpi=300)

            for page_img in raw_pages:
                self._add_page(page_img)

            self.lbl_file_status.config(text=f"{os.path.basename(file_path)} ({self.total_pages} Hal)", foreground="green")
            self.btn_print.config(state="normal")
            self.btn_select_all.config(state="normal")
            self.btn_deselect_all.config(state="normal")
            self.btn_edit_pattern.config(state="normal")
            
            if self.total_pages > 0: self.update_preview_display(0)
        except Exception:
            print("\n[GUI ERROR] Gagal load PDF:"); traceback.print_exc()
            messagebox.showerror("Error", "Gagal memproses berkas dokumen PDF.")

    def import_files(self):
        """Impor satu atau beberapa berkas -- boleh campur PDF dan gambar
        (JPG/PNG) sekaligus dalam satu dialog -- sebagai halaman TAMBAHAN,
        tanpa menghapus halaman yang sudah ada di sesi ini. Kalau berkasnya
        PDF, semua halamannya dirender (dpi=300) dan ditambahkan satu per
        satu. Semua masuk ke pipeline raw_pages yang sama supaya crop
        manual & preview bekerja persis sama untuk PDF maupun gambar."""
        file_paths = filedialog.askopenfilenames(
            initialdir=self.initial_dir,
            filetypes=[
                ("PDF & Gambar", "*.pdf *.jpg *.jpeg *.png"),
                ("PDF Files", "*.pdf"),
                ("Gambar", "*.jpg *.jpeg *.png"),
                ("Semua File", "*.*"),
            ]
        )
        if not file_paths: return

        self.lbl_file_status.config(text="Mengimpor berkas...", foreground="blue")
        self.root.update_idletasks()
        added_pdf, added_img = 0, 0
        try:
            for path in file_paths:
                ext = os.path.splitext(path)[1].lower()
                if ext == ".pdf":
                    if not self.pdf_path:
                        self.pdf_path = path
                    pdf_pages = convert_from_path(path, dpi=300)
                    base_name = os.path.basename(path)
                    for p_i, page_img in enumerate(pdf_pages):
                        self._add_page(page_img, label=f"Halaman {len(self.raw_pages)+1} ({base_name} hal.{p_i+1})")
                        added_pdf += 1
                elif ext in (".jpg", ".jpeg", ".png"):
                    img = Image.open(path).convert("RGB")
                    self._add_page(img, label=f"Halaman {len(self.raw_pages)+1} (Gambar: {os.path.basename(path)})")
                    added_img += 1

            ket = []
            if added_pdf: ket.append(f"{added_pdf} hal. dari PDF")
            if added_img: ket.append(f"{added_img} gambar")
            self.lbl_file_status.config(
                text=f"{self.total_pages} Hal siap ({', '.join(ket) if ket else 'tidak ada berkas valid'})",
                foreground="green"
            )
            self.btn_print.config(state="normal")
            self.btn_select_all.config(state="normal")
            self.btn_deselect_all.config(state="normal")
            self.btn_edit_pattern.config(state="normal")
            if self.total_pages > 0:
                self.update_preview_display(self.total_pages - 1)
        except Exception:
            print("\n[GUI ERROR] Gagal impor berkas:"); traceback.print_exc()
            messagebox.showerror("Error", "Gagal memproses salah satu berkas PDF/gambar.")

    def _add_page(self, img, label=None):
        """Tambahkan satu halaman (PIL Image) ke akhir sesi yang sedang
        berjalan: daftar raw_pages, checkbox pilih, crop (ikut mode/pola
        aktif), dan baris UI-nya. Dipakai bersama oleh load_pdf & import_files
        supaya PDF dan gambar diperlakukan identik."""
        idx = len(self.raw_pages)
        self.raw_pages.append(img)
        self.total_pages = len(self.raw_pages)
        self.selected_pages[idx] = tk.BooleanVar(value=True)
        self.cropped_pages_images[idx] = self.smart_crop_and_resize_gui(idx, img)
        self._build_page_row(idx, label=label)
        return idx

    def _build_page_row(self, i, label=None):
        """Bikin satu baris di daftar halaman: checkbox pilih, tag mode crop,
        tombol Crop Manual, dan tombol Preview."""
        row = ttk.Frame(self.scrollable_frame)
        row.pack(fill="x", anchor="w", pady=2, padx=5)
        ttk.Checkbutton(row, text=label or f"Halaman {i+1}", variable=self.selected_pages[i]).pack(side="left", padx=5)

        crop_label = ttk.Label(row, text=self._crop_tag_text(i), foreground="gray", font=("Helvetica", 8))
        crop_label.pack(side="left", padx=(2, 8))
        self.row_crop_labels[i] = crop_label

        ttk.Button(row, text="Preview", width=9, command=lambda idx=i: self.update_preview_display(idx)).pack(side="right", padx=3)
        ttk.Button(row, text="Crop Manual", width=11, command=lambda idx=i: self.open_crop_editor(idx)).pack(side="right", padx=3)

    def _crop_tag_text(self, i):
        if i in self.page_crop_overrides:
            top_mm, bottom_mm = self.page_crop_overrides[i]
            return f"[Manual: {top_mm}mm / {bottom_mm}mm]"
        if self.crop_mode == "manual":
            return f"[Pola: {self.manual_top_mm}mm / {self.manual_bottom_mm}mm]"
        return "[Auto]"

    def _recompute_all_pages(self):
        """Hitung ulang cropped_pages_images utk SEMUA halaman sesuai
        crop_mode/override yang aktif saat ini, lalu refresh tag baris &
        preview. Dipakai setiap kali mode crop berubah secara global."""
        for i, raw_page in enumerate(self.raw_pages):
            self.cropped_pages_images[i] = self.smart_crop_and_resize_gui(i, raw_page)
            if i in self.row_crop_labels:
                self.row_crop_labels[i].config(text=self._crop_tag_text(i))
        if self.total_pages > 0:
            self.update_preview_display(self.current_preview_idx)

    def on_crop_mode_changed(self):
        """Dipanggil saat pengguna klik radio button 'Otomatis' / 'Manual'
        di section 3. Mode Crop."""
        new_mode = self.crop_mode_var.get()
        self.crop_mode = new_mode

        if new_mode == "auto":
            # Auto berarti auto utk SEMUA halaman -- override per-halaman
            # (kalau ada) dihapus supaya tidak ada halaman yang "nyangkut" manual.
            self.page_crop_overrides.clear()
            self._recompute_all_pages()
            self.lbl_file_status.config(text="Mode Otomatis (Smart Crop) aktif untuk semua halaman.", foreground="green")
        else:
            self._recompute_all_pages()
            if self.manual_top_mm == 0 and self.manual_bottom_mm == 0 and not self.page_crop_overrides:
                self.lbl_file_status.config(
                    text="Mode Manual aktif. Klik 'Atur Pola Crop...' atau tombol 'Crop Manual' "
                         "di halaman manapun, lalu 'Terapkan ke SEMUA Halaman'.",
                    foreground="blue"
                )
            else:
                self.lbl_file_status.config(
                    text=f"Mode Manual aktif ({self.manual_top_mm}mm atas / {self.manual_bottom_mm}mm bawah).",
                    foreground="green"
                )

    def open_crop_editor_for_current(self):
        """Tombol pintas 'Atur Pola Crop...' -- buka editor untuk halaman
        yang sedang di-preview (atau halaman pertama kalau belum ada yang dipilih)."""
        if not self.raw_pages:
            messagebox.showinfo("Info", "Buka PDF atau tambah gambar dulu sebelum mengatur crop.")
            return
        self.open_crop_editor(self.current_preview_idx)

    def open_crop_editor(self, index):
        if index < 0 or index >= len(self.raw_pages):
            return
        CropEditorWindow(self.root, self, index)

    def on_crop_editor_saved(self, index):
        """Dipanggil dari CropEditorWindow setelah 'Simpan Halaman Ini'."""
        if index in self.row_crop_labels:
            self.row_crop_labels[index].config(text=self._crop_tag_text(index))
        if index == self.current_preview_idx:
            self.update_preview_display(index)

    def apply_manual_crop_pattern_to_all(self, top_mm, bottom_mm):
        """Broadcast satu pola offset atas/bawah (fixed mm) ke SEMUA halaman.
        Override khusus per-halaman dihapus supaya pola global konsisten
        berlaku merata; bagian tengah tiap halaman tetap otomatis mengikuti
        panjang aslinya masing-masing. Otomatis pindah ke Mode Manual
        (radio button ikut ter-update) karena ini jelas maksud pengguna."""
        self.crop_mode = "manual"
        self.crop_mode_var.set("manual")
        self.manual_top_mm = top_mm
        self.manual_bottom_mm = bottom_mm
        self.page_crop_overrides.clear()

        self._recompute_all_pages()

        self.lbl_file_status.config(
            text=f"Pola crop manual diterapkan ke semua {self.total_pages} halaman "
                 f"({top_mm}mm atas / {bottom_mm}mm bawah)", foreground="green"
        )

    def update_preview_display(self, index):
        if index not in self.cropped_pages_images: return
        self.current_preview_idx = index
        img = self.cropped_pages_images[index]
        
        c_w, c_h = self.preview_canvas.winfo_width(), self.preview_canvas.winfo_height()
        if c_w <= 1: c_w, c_h = 300, 450
        
        display_img = img.copy()
        d_w, d_h = display_img.size
        ratio = min(c_w / d_w, c_h / d_h)
        display_img = display_img.resize((int(d_w * ratio), int(d_h * ratio)), Image.Resampling.NEAREST)
        
        self.tk_preview_img = ImageTk.PhotoImage(display_img)
        self.preview_canvas.delete("all")
        self.preview_canvas.create_image(c_w//2, c_h//2, anchor="center", image=self.tk_preview_img)
        
        # Update teks nomor halaman navigasi multi-page
        self.lbl_page_num.config(text=f"{index+1} / {self.total_pages}")
        self.lbl_preview_info.config(text=f"Resolusi Output Cetak Fisik: {d_w}x{d_h} Px")
        self.btn_prev.config(state="normal" if index > 0 else "disabled")
        self.btn_next.config(state="normal" if index < self.total_pages - 1 else "disabled")

    def prev_page(self):
        if self.current_preview_idx > 0: 
            self.update_preview_display(self.current_preview_idx - 1)

    def next_page(self):
        if self.current_preview_idx < self.total_pages - 1: 
            self.update_preview_display(self.current_preview_idx + 1)

    def select_all(self):
        for v in self.selected_pages.values(): 
            v.set(True)

    def deselect_all(self):
        for v in self.selected_pages.values(): 
            v.set(False)

    def clear_preview(self):
        self.preview_canvas.delete("all")
        self.lbl_page_num.config(text="0 / 0")
        self.btn_prev.config(state="disabled")
        self.btn_next.config(state="disabled")

    def print_selected(self):
        to_print = [idx for idx, v in self.selected_pages.items() if v.get()]
        if not to_print: 
            return messagebox.showwarning("Peringatan", "Pilih halaman yang ingin dicetak!")
        try:
            self.btn_print.config(state="disabled", text="MENCETAK...")
            self.root.update_idletasks()
            execute_printing(to_print, self.cropped_pages_images, paper_width_mm=self.paper_width_mm)
            messagebox.showinfo("Sukses", "Dokumen sukses dicetak!")
        except Exception:
            print("\n[GUI ERROR] Alur cetak gagal:")
            traceback.print_exc()
            messagebox.showerror("Error", "Gagal mengirim data ke hardware printer.")
            self.check_printer_connection()
        finally: 
            self.btn_print.config(state="normal", text="CETAK HALAMAN TERPILIH")

if __name__ == "__main__":
    root = tk.Tk()
    app = PeriPageApp(root)
    root.mainloop()
