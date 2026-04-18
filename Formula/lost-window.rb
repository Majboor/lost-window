class LostWindow < Formula
  desc "Recover lost macOS app windows and force them back onscreen"
  homepage "https://github.com/Majboor/lost-window"
  head "https://github.com/Majboor/lost-window.git", branch: "main"

  def install
    libexec.install Dir["bin/*"]
    pkgshare.install "README.md"
    pkgshare.install "raycast"
    pkgshare.install "shortcuts"
    bin.write_exec_script libexec/"bin/lost-window"
  end

  def caveats
    <<~EOS
      Grant Accessibility permission to whichever app launches `lost-window`.

      For native launcher apps after install:
        lost-window install-apps
    EOS
  end

  test do
    assert_match "Missing command", shell_output("#{bin}/lost-window __bad_command__ 2>&1", 1)
  end
end
