import os
import tkinter as tk
import traceback
from tkinter import filedialog, messagebox, ttk
from PIL import Image, ImageChops, ImageTk
from pdf2image import convert_from_path
from peripage_logic import (
    smart_crop_and_resize, execute_printing,
    load_paper_width_mm, save_paper_width_mm, SUPPORTED_PAPER_WIDTHS_MM
)

class PeriPageApp:
    def __init__(self, root):
        self.root = root
        self.root.title("PeriPage A9 - PDF Smart Printer & Preview")
        self.root.geometry("850x680")
        self.root.resizable(False, False)

        self.printer_connected = False
        self.pdf_path = ""
        self.raw_pages = []              # Halaman mentah hasil render PDF (belum di-crop), disimpan agar bisa direproses saat ganti kertas
        self.cropped_pages_images = {}   
        self.selected_pages = {}         
        self.current_preview_idx = 0
        self.total_pages = 0

        # Otomatis muat setting lebar kertas terakhir yang tersimpan
        self.paper_width_mm = load_paper_width_mm()

        self.initial_dir = os.path.expanduser("~/Downloads")
        if not os.path.exists(self.initial_dir):
            self.initial_dir = os.path.expanduser("~")

        self.create_widgets()

    def create_widgets(self):
        main_frame = ttk.Frame(self.root, padding=10)
        main_frame.pack(fill="both", expand=True)

        left_panel = ttk.Frame(main_frame)
        left_panel.pack(side="left", fill="both", expand=True, padx=(0, 10))

        right_panel = ttk.LabelFrame(main_frame, text=" Live Preview (What You See Is What You Print) ", padding=10, width=340)
        right_panel.pack(side="right", fill="both")

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

        # 3. Pilih PDF
        self.file_frame = ttk.LabelFrame(left_panel, text=" 3. Pilih Dokumen PDF ", padding=10)
        self.file_frame.pack(fill="x", pady=5)
        self.btn_browse = ttk.Button(self.file_frame, text="Buka PDF", command=self.load_pdf, state="disabled")
        self.btn_browse.pack(side="left", padx=5)
        self.lbl_file_status = ttk.Label(self.file_frame, text="Hubungkan printer dulu", wraplength=300, foreground="gray")
        self.lbl_file_status.pack(side="left", padx=10)

        # 4. Daftar Halaman
        self.page_frame = ttk.LabelFrame(left_panel, text=" 4. Daftar Halaman ", padding=10)
        self.page_frame.pack(fill="both", expand=True, pady=5)

        self.canvas = tk.Canvas(self.page_frame, borderwidth=0, highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(self.page_frame, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = ttk.Frame(self.canvas)
        self.scrollable_frame.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")

        # Tombol Kendali & Cetak
        self.bulk_frame = ttk.Frame(left_panel, padding=5)
        self.bulk_frame.pack(fill="x", pady=5)
        self.btn_select_all = ttk.Button(self.bulk_frame, text="Pilih Semua", command=self.select_all, state="disabled")
        self.btn_select_all.pack(side="left", padx=5)
        self.btn_deselect_all = ttk.Button(self.bulk_frame, text="Kosongkan", command=self.deselect_all, state="disabled")
        self.btn_deselect_all.pack(side="left", padx=5)

        self.btn_print = ttk.Button(left_panel, text="CETAK HALAMAN TERPILIH", command=self.print_selected, state="disabled")
        self.btn_print.pack(fill="x", ipady=10, pady=5)

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
                if not self.pdf_path: self.lbl_file_status.config(text="Printer siap. Silakan pilih PDF.", foreground="black")
            else: raise Exception("Device not found")
        except Exception:
            self.printer_connected = False
            self.lbl_conn_status.config(text="TIDAK TERDETEKSI", foreground="red")
            self.btn_browse.config(state="disabled")
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
                self.cropped_pages_images[i] = self.smart_crop_and_resize_gui(raw_page)
            self.lbl_file_status.config(text=f"{os.path.basename(self.pdf_path)} ({self.total_pages} Hal) — kertas {new_width}mm", foreground="green")
            self.update_preview_display(self.current_preview_idx)

    def smart_crop_and_resize_gui(self, pil_img):
        """Memanggil fungsi pemotong presisi terpusat dari file logic, sesuai lebar kertas aktif"""
        return smart_crop_and_resize(pil_img, paper_width_mm=self.paper_width_mm)

    def load_pdf(self):
        file_path = filedialog.askopenfilename(initialdir=self.initial_dir, filetypes=[("PDF Files", "*.pdf")])
        if not file_path: return
        self.pdf_path = file_path
        self.lbl_file_status.config(text="Sedang memproses PDF & Smart Crop...", foreground="blue")
        
        for w in self.scrollable_frame.winfo_children(): w.destroy()
        self.selected_pages.clear()
        self.cropped_pages_images.clear()
        self.raw_pages = []
        self.clear_preview()

        try:
            self.root.update_idletasks()
            raw_pages = convert_from_path(file_path, dpi=300)
            self.raw_pages = raw_pages
            self.total_pages = len(raw_pages)
            
            for i in range(self.total_pages):
                var = tk.BooleanVar(value=True)
                self.selected_pages[i] = var
                
                # Proses gambar tunggal di sini untuk dipakai bersama oleh Preview dan Printer
                self.cropped_pages_images[i] = self.smart_crop_and_resize_gui(raw_pages[i])
                
                row = ttk.Frame(self.scrollable_frame)
                row.pack(fill="x", anchor="w", pady=2, padx=5)
                ttk.Checkbutton(row, text=f"Halaman {i+1}", variable=var).pack(side="left", padx=5)
                ttk.Button(row, text="Preview", width=10, command=lambda idx=i: self.update_preview_display(idx)).pack(side="right", padx=5)

            self.lbl_file_status.config(text=f"{os.path.basename(file_path)} ({self.total_pages} Hal)", foreground="green")
            self.btn_print.config(state="normal")
            self.btn_select_all.config(state="normal")
            self.btn_deselect_all.config(state="normal")
            
            if self.total_pages > 0: self.update_preview_display(0)
        except Exception:
            print("\n[GUI ERROR] Gagal load PDF:"); traceback.print_exc()
            messagebox.showerror("Error", "Gagal memproses berkas dokumen PDF.")

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
