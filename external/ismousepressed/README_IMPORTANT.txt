In order to work, you will need to execute a couple of lines in matlab commandline before.

1) extract the content of this zip into a folder.
2) go to this folder in matlab 
3) run: loadlibrary('user32.dll','user32.h')

That's it, now you can use function ismousepressed() at will!