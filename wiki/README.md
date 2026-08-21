# wiki/ — source for the GitHub wiki

These pages are the content for <https://github.com/dstolz/MABR/wiki>, which the
app's Help ▸ MABR Wiki menu item opens (`+mabr/+ui/App.m`).

GitHub wikis are a separate git repository. To publish:

```sh
git clone https://github.com/dstolz/MABR.wiki.git /tmp/mabr-wiki
cp wiki/*.md /tmp/mabr-wiki/
cd /tmp/mabr-wiki
git add -A && git commit -m "Populate MABR wiki" && git push
```

Note: the wiki repo does not exist until at least one page has been created
through the web UI. Create the Home page there once, then the clone above works.

Filenames map to page titles with `-` standing in for a space, so
`Running-a-Session.md` becomes the page **Running a Session** and is linked as
`[[Running a Session]]`. `_Sidebar.md` renders as the navigation sidebar on
every page.

## Class reference pages

`Class-Reference.md` is the index; one page per class sits beside it, named
`<fully.qualified.Name>-Class-Reference.md` — e.g. `mabr.acq.Engine-Class-Reference.md`
becomes the page **mabr.acq.Engine Class Reference** and is linked as
`[[mabr.acq.Engine|mabr.acq.Engine-Class-Reference]]`. Same convention as the
[epsych2 wiki](https://github.com/dstolz/epsych2/wiki/Class-Reference).

Diagrams are [mermaid](https://mermaid.js.org) fenced blocks, which GitHub wikis render
natively — no images to regenerate.

Source links point at the **`refactor`** branch, since `+mabr` does not exist on `master`.
Update them at cutover:

```sh
sed -i 's#/blob/refactor/#/blob/master/#g; s#/tree/refactor/#/tree/master/#g' wiki/*.md
```
