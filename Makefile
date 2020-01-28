
install:
	mkdir -p ~/bin
	install -m 755 wheel2pkg ~/bin
	mkdir -p ~/lib/template
	install -m 444 specfile ~/lib/template

