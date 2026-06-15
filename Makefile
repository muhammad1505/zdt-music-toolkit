PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share/zdt
DOCDIR = $(PREFIX)/share/doc/zdt

.PHONY: all install uninstall clean

all:
	@echo "Zaki Downloader Tools (ZDT)"
	@echo ""
	@echo "Usage:"
	@echo "  make install     - Install ZDT to $(BINDIR)"
	@echo "  make uninstall   - Remove ZDT from your system"

install:
	@echo "Installing ZDT..."
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 zdt.sh $(DESTDIR)$(BINDIR)/zdt
	install -d $(DESTDIR)$(SHAREDIR)
	install -d $(DESTDIR)$(DOCDIR)
	@echo "Installation complete."
	@echo "Run 'zdt' to start the application."

uninstall:
	@echo "Uninstalling ZDT..."
	rm -f $(DESTDIR)$(BINDIR)/zdt
	rm -rf $(DESTDIR)$(SHAREDIR)
	rm -rf $(DESTDIR)$(DOCDIR)
	@echo "Uninstallation complete."
