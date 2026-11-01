#!/usr/bin/env python3
"""
Distraction-Free Pomodoro Focus Timer for Study OS.
Features standard 25-minute study sprints, 5-minute short breaks, and 15-minute long breaks.
Provides clean visual countdown and progress indicators with zero acoustic noise.
Compatible with GTK3 (native Linux) and Tkinter (fallback).
"""

import sys
import time

INTERVALS = {
    "Focus (25m)": 25 * 60,      # 25 minutes (1500 seconds)
    "Short Break (5m)": 5 * 60,   # 5 minutes (300 seconds)
    "Long Break (15m)": 15 * 60,  # 15 minutes (900 seconds)
}


def format_time(seconds: int) -> str:
    """Format total seconds into MM:SS format."""
    mins, secs = divmod(seconds, 60)
    return f"{mins:02d}:{secs:02d}"


def run_gtk3():
    """Run native GTK3 graphical timer."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, GLib

    class PomodoroGtkApp(Gtk.Window):
        def __init__(self):
            super().__init__(title="Study Timer")
            self.set_default_size(320, 240)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.set_resizable(False)

            self.current_mode = "Focus (25m)"
            self.total_duration = INTERVALS[self.current_mode]
            self.time_left = self.total_duration
            self.is_running = False
            self.timer_source_id = None

            # Layout Box
            main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            main_box.set_margin_top(16)
            main_box.set_margin_bottom(16)
            main_box.set_margin_start(20)
            main_box.set_margin_end(20)
            self.add(main_box)

            # Mode Selector Combo
            self.mode_combo = Gtk.ComboBoxText()
            for mode_name in INTERVALS:
                self.mode_combo.append_text(mode_name)
            self.mode_combo.set_active(0)
            self.mode_combo.connect("changed", self.on_mode_changed)
            main_box.pack_start(self.mode_combo, False, False, 0)

            # Countdown Label
            self.time_label = Gtk.Label()
            self.update_time_display()
            main_box.pack_start(self.time_label, True, True, 4)

            # Visual Progress Bar
            self.progress_bar = Gtk.ProgressBar()
            self.progress_bar.set_fraction(1.0)
            main_box.pack_start(self.progress_bar, False, False, 4)

            # Status Banner
            self.status_label = Gtk.Label(label="Ready to focus")
            main_box.pack_start(self.status_label, False, False, 0)

            # Button Controls
            button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            main_box.pack_start(button_box, False, False, 0)

            self.toggle_button = Gtk.Button(label="Start")
            self.toggle_button.connect("clicked", self.on_toggle_clicked)
            button_box.pack_start(self.toggle_button, True, True, 0)

            self.reset_button = Gtk.Button(label="Reset")
            self.reset_button.connect("clicked", self.on_reset_clicked)
            button_box.pack_start(self.reset_button, True, True, 0)

        def update_time_display(self):
            display_str = format_time(self.time_left)
            self.time_label.set_markup(
                f"<span font='44' weight='bold' color='#cdd6f4'>{display_str}</span>"
            )

        def update_progress(self):
            if self.total_duration > 0:
                fraction = max(0.0, min(1.0, self.time_left / self.total_duration))
                self.progress_bar.set_fraction(fraction)

        def on_tick(self):
            if self.is_running and self.time_left > 0:
                self.time_left -= 1
                self.update_time_display()
                self.update_progress()

                if self.time_left == 0:
                    self.is_running = False
                    self.toggle_button.set_label("Start")
                    # Zero acoustic noise: completely silent visual completion state
                    self.status_label.set_text("Interval Complete! Time to switch.")
                    return False
                return True
            return False

        def on_toggle_clicked(self, widget):
            self.is_running = not self.is_running
            if self.is_running:
                self.toggle_button.set_label("Pause")
                self.status_label.set_text("Focus in progress...")
                self.timer_source_id = GLib.timeout_add_seconds(1, self.on_tick)
            else:
                self.toggle_button.set_label("Resume")
                self.status_label.set_text("Paused")
                if self.timer_source_id:
                    GLib.source_remove(self.timer_source_id)

        def on_reset_clicked(self, widget):
            self.is_running = False
            self.toggle_button.set_label("Start")
            self.status_label.set_text("Ready to focus")
            if self.timer_source_id:
                GLib.source_remove(self.timer_source_id)
            self.total_duration = INTERVALS[self.current_mode]
            self.time_left = self.total_duration
            self.update_time_display()
            self.update_progress()

        def on_mode_changed(self, combo):
            selected = combo.get_active_text()
            if selected and selected in INTERVALS:
                self.current_mode = selected
                self.on_reset_clicked(None)

    window = PomodoroGtkApp()
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()


def run_tkinter():
    """Run standard Tkinter graphical timer fallback."""
    import tkinter as tk
    from tkinter import ttk

    root = tk.Tk()
    root.title("Study Timer")
    root.geometry("320x240")
    root.resizable(False, False)
    root.configure(bg="#1e1e2e")

    current_mode = tk.StringVar(value="Focus (25m)")
    time_left = [INTERVALS["Focus (25m)"]]
    total_duration = [INTERVALS["Focus (25m)"]]
    is_running = [False]
    timer_after_id = [None]

    # Mode Selector
    mode_frame = tk.Frame(root, bg="#1e1e2e")
    mode_frame.pack(pady=10)
    mode_combo = ttk.Combobox(
        mode_frame,
        textvariable=current_mode,
        values=list(INTERVALS.keys()),
        state="readonly",
        width=18,
    )
    mode_combo.pack()

    # Time Display
    time_label = tk.Label(
        root,
        text=format_time(time_left[0]),
        font=("Sans", 40, "bold"),
        fg="#cdd6f4",
        bg="#1e1e2e",
    )
    time_label.pack(pady=4)

    # Progress Bar
    progress = ttk.Progressbar(root, orient="horizontal", length=240, mode="determinate")
    progress.pack(pady=6)
    progress["value"] = 100

    status_label = tk.Label(
        root,
        text="Ready to focus",
        font=("Sans", 10),
        fg="#a6adc8",
        bg="#1e1e2e",
    )
    status_label.pack(pady=2)

    button_frame = tk.Frame(root, bg="#1e1e2e")
    button_frame.pack(pady=10)

    btn_toggle = tk.Button(
        button_frame,
        text="Start",
        width=10,
        font=("Sans", 10, "bold"),
        bg="#313244",
        fg="#cdd6f4",
        activebackground="#45475a",
        activeforeground="#cdd6f4",
    )
    btn_toggle.pack(side="left", padx=5)

    btn_reset = tk.Button(
        button_frame,
        text="Reset",
        width=10,
        font=("Sans", 10, "bold"),
        bg="#313244",
        fg="#cdd6f4",
        activebackground="#45475a",
        activeforeground="#cdd6f4",
    )
    btn_reset.pack(side="right", padx=5)

    def tick():
        if is_running[0] and time_left[0] > 0:
            time_left[0] -= 1
            time_label.config(text=format_time(time_left[0]))
            fraction = (time_left[0] / total_duration[0]) * 100
            progress["value"] = fraction
            if time_left[0] == 0:
                is_running[0] = False
                btn_toggle.config(text="Start")
                # Zero acoustic noise: completely silent visual completion
                status_label.config(text="Interval Complete! Time to switch.", fg="#a6e3a1")
                return
            timer_after_id[0] = root.after(1000, tick)

    def toggle():
        is_running[0] = not is_running[0]
        if is_running[0]:
            btn_toggle.config(text="Pause")
            status_label.config(text="Focus in progress...", fg="#89b4fa")
            timer_after_id[0] = root.after(1000, tick)
        else:
            btn_toggle.config(text="Resume")
            status_label.config(text="Paused", fg="#fab387")
            if timer_after_id[0]:
                root.after_cancel(timer_after_id[0])

    def reset():
        is_running[0] = False
        btn_toggle.config(text="Start")
        status_label.config(text="Ready to focus", fg="#a6adc8")
        if timer_after_id[0]:
            root.after_cancel(timer_after_id[0])
        mode_val = current_mode.get()
        total_duration[0] = INTERVALS.get(mode_val, 25 * 60)
        time_left[0] = total_duration[0]
        time_label.config(text=format_time(time_left[0]))
        progress["value"] = 100

    def on_mode_change(event):
        reset()

    mode_combo.bind("<<ComboboxSelected>>", on_mode_change)
    btn_toggle.config(command=toggle)
    btn_reset.config(command=reset)

    root.mainloop()


def main():
    """Main entrypoint selecting GTK3 or Tkinter fallback."""
    try:
        run_gtk3()
    except (ImportError, ValueError):
        try:
            run_tkinter()
        except ImportError:
            print("Notice: Graphical environment unavailable. Running in terminal mode.")
            print("Study Sprint: 25 minutes.")


if __name__ == "__main__":
    main()
