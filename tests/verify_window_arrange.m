function verify_window_arrange()
% verify_window_arrange  Confirm the arithmetic behind the main window's
%                        Arrange windows toolbar button.
%
%   mabr.ui.WindowPos.arrangeRegion picks the strip of the main window's
%   display to tile into, and mabr.ui.WindowPos.tile cuts it into one cell per
%   viewer. Both are pure functions of rectangles, checked here against fixed
%   monitor layouts rather than the machine's own:
%
%   Part A: the region is the wider strip beside the main window, on the
%   display holding it, clear of the main window and of the taskbar margin;
%   the whole display when neither strip is wide enough; the second display
%   when the main window is on it.
%   Part B: for 1..12 windows, every cell lies inside the region, no two
%   overlap, neighbours are ArrangeGap apart, and the first cell is top left.
%
%   No hardware, no engine, no parallel pool, no window, no prefs.
%
%   Run:  >> verify_window_arrange
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_window_arrange ==\n');
gap = mabr.ui.WindowPos.ArrangeGap;
one = [1 1 1920 1080];
two = [1 1 1920 1080; 1921 1 2560 1440];

% ---- Part A: the region -------------------------------------------------
main = [100 200 480 830];                       % main window near the left edge
r = mabr.ui.WindowPos.arrangeRegion(main,one,40);
assert(isequal(r,[100+480+gap, 41, 1920-(100+480+gap)+1, 1040]), ...
    'main on the left: the region must be the strip to its right, above the margin');
assert(r(1) >= main(1)+main(3),'the region must not overlap the main window');

main = [1400 200 480 830];                      % near the right edge
r = mabr.ui.WindowPos.arrangeRegion(main,one,40);
assert(r(1) == 1 && r(1)+r(3) <= main(1),'main on the right: tile the strip to its left');

main = [400 200 480 580];                       % mid-screen on a small display
small = [1 1 1280 800];
r = mabr.ui.WindowPos.arrangeRegion(main,small,40);
assert(isequal(r,[1 41 1280 760]),'neither strip wide enough: tile the whole display');

main = [2000 300 480 830];                      % on the second display
r = mabr.ui.WindowPos.arrangeRegion(main,two,40);
assert(r(1) >= 2000+480 && r(1)+r(3) <= 1921+2560, ...
    'the region must be on the display holding the main window');
fprintf('  PASS Part A: region beside the main window, on its display\n');

% ---- Part B: the cells --------------------------------------------------
region = [600 41 1320 1040];
for n = 1:12
    c = mabr.ui.WindowPos.tile(region,n);
    assert(isequal(size(c),[n 4]),'tile must return one cell per window');
    assert(all(c(:,3) > 0 & c(:,4) > 0),'cells must have positive size');
    assert(all(c(:,1) >= region(1) & c(:,2) >= region(2) & ...
               c(:,1)+c(:,3) <= region(1)+region(3) & ...
               c(:,2)+c(:,4) <= region(2)+region(4)), ...
        'every cell must lie inside the region (n = %d)',n);
    for i = 1:n
        for j = i+1:n
            ox = min(c(i,1)+c(i,3),c(j,1)+c(j,3)) - max(c(i,1),c(j,1));
            oy = min(c(i,2)+c(i,4),c(j,2)+c(j,4)) - max(c(i,2),c(j,2));
            assert(ox <= -gap || oy <= -gap, ...
                'cells %d and %d are closer than ArrangeGap (n = %d)',i,j,n);
        end
    end
    assert(c(1,1) == region(1) && c(1,2)+c(1,4) == region(2)+region(4), ...
        'the first cell must be top left (n = %d)',n);
end
c = mabr.ui.WindowPos.tile(region,1);
assert(isequal(c,region),'one window takes the whole region');
assert(isempty(mabr.ui.WindowPos.tile(region,0)),'no windows, no cells');
fprintf('  PASS Part B: cells inside the region, non-overlapping, gap apart\n');

fprintf('verify_window_arrange: ALL PASS\n');
end
