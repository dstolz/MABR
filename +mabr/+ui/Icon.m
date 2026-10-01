classdef Icon
% mabr.ui.Icon  MABR's toolbar pictograms, drawn as anti-aliased vector art.
%
%   Every toolbar button MABR puts up -- the main window's, the trace
%   organizer's, and the notes button both of them carry -- is drawn here,
%   in one palette, so the toolbars read as one set and each button says
%   what it does before anyone hovers for its tooltip:
%
%       cdata = mabr.ui.Icon.toolbar('live',app.Toolbar);
%       uipushtool(app.Toolbar,'CData',cdata,...);
%
%   A glyph is drawn in pixel coordinates (x to the right, y down, 0..16)
%   from a handful of shape primitives -- boxes, rounded boxes, discs,
%   strokes, polygons and arcs -- rasterized at Supersample x and
%   box-filtered down, so curves and diagonals come out anti-aliased rather
%   than staircased. Straight strokes sit on whole pixels where they can,
%   which is what keeps them crisp at 16 px.
%
%   A toolbar button's CData has binary transparency only (NaN or not), so
%   a partly covered edge pixel cannot be partly transparent. It is blended
%   instead against the background of the toolbar it will sit on
%   (background(toolbar)), and a pixel covered less than MinAlpha is left
%   transparent. render() returns the unflattened colour and coverage, for
%   tests and for anything that can carry real alpha.
%
%   Colour means the same thing on every button: blue is the data (a trace,
%   a window, a disk), orange is what the button does to it (a marker
%   dropped, a scale changed, the condition now playing), green is done or
%   added, and red is live or destructive.
%
%       mabr.ui.Icon.preview()            % every glyph, 1x and enlarged
%       img = mabr.ui.Icon.sheet(names,8);% the same as an RGB image
%
%   Used by mabr.ui.App, mabr.ui.TraceOrganizer and mabr.ui.Notes.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        Size        = 16        % toolbar CData is 16 x 16
        Supersample = 8         % subpixels per pixel, per axis
        MinAlpha    = 0.2       % coverage below which a pixel is left transparent
        Background  = [0.94 0.94 0.94]  % toolbar colour when it cannot be read

        % One palette for every glyph. Kept here rather than per caller so
        % the trace organizer's blue is the main window's blue.
        Palette = struct( ...
            'Ink',      [0.16 0.26 0.42], ...  % outlines, axes, frames
            'Blue',     [0.00 0.45 0.74], ...  % data: traces, title bars
            'Sky',      [0.86 0.93 1.00], ...  % pale fill behind data
            'Orange',   [0.93 0.50 0.10], ...  % the action
            'Green',    [0.20 0.63 0.30], ...  % done, add
            'Red',      [0.84 0.19 0.16], ...  % live, destructive
            'Grey',     [0.62 0.65 0.70], ...  % inactive, upcoming
            'Track',    [0.82 0.84 0.87], ...  % the unfilled part of a gauge
            'Paper',    [1.00 1.00 1.00], ...
            'Note',     [1.00 0.88 0.42], ...  % notepad paper
            'Folder',   [0.98 0.78 0.30], ...
            'FolderBk', [0.85 0.60 0.16], ...
            'Screen',   [0.10 0.14 0.21], ...  % monitor glass
            'Phosphor', [0.35 0.95 0.55], ...  % a trace on that glass
            'Steel',    [0.80 0.83 0.87], ...
            'Wood',     [0.96 0.80 0.58], ...
            'Eraser',   [0.95 0.55 0.62])

        % Three of MATLAB's default colours (lines(7)), which the trace
        % organizer colours its stack with, so the 'traces' glyph looks like
        % the window it opens. The third default, yellow, is left out: it
        % all but vanishes on a light toolbar.
        Series = [0.000 0.447 0.741
                  0.850 0.325 0.098
                  0.494 0.184 0.556]
    end

    methods (Static)
        function n = names()
            % Every glyph render() knows, main-window ones first.
            n = {'live','metrics','traces','stim','progress','order', ...
                 'notes','front','arrange','pin','help', ...
                 'grow','shrink','spread','squeeze','peaks','inspect', ...
                 'save','load','trash','keys'};
        end

        function c = toolbar(name,bg)
            % 16x16x3 CData for a uipushtool/uitoggletool, NaN where
            % transparent. BG is the toolbar itself (its colour is read) or
            % an RGB triple; omitted, the usual light grey. Cached per glyph
            % and background, since a closed trace organizer rebuilds its
            % toolbar every time it is shown again.
            persistent cache
            if nargin < 2 || isempty(bg)
                bg = mabr.ui.Icon.Background;
            elseif ~isnumeric(bg)
                bg = mabr.ui.Icon.background(bg);
            end
            if isempty(cache), cache = containers.Map(); end
            key = sprintf('%s|%.4f|%.4f|%.4f',name,bg);
            if isKey(cache,key)
                c = cache(key);
                return;
            end
            [rgb,alpha] = mabr.ui.Icon.render(name);
            c = mabr.ui.Icon.flatten(rgb,alpha,bg);
            cache(key) = c;
        end

        function bg = background(tb)
            % The colour a toolbar paints behind its buttons. A uifigure's
            % uitoolbar has a BackgroundColor; a classic figure's does not,
            % and anything unreadable falls back to the usual light grey.
            bg = mabr.ui.Icon.Background;
            try
                if isprop(tb,'BackgroundColor')
                    v = double(tb.BackgroundColor);
                    if isequal(size(v),[1 3]) && all(isfinite(v)) ...
                            && all(v >= 0 & v <= 1)
                        bg = v;
                    end
                end
            catch
            end
        end

        function c = flatten(rgb,alpha,bg)
            % Composite RGB over BG by coverage ALPHA, leaving a pixel
            % covered less than MinAlpha transparent (NaN in every plane).
            c = rgb.*alpha + reshape(bg,1,1,3).*(1-alpha);
            c(repmat(alpha < mabr.ui.Icon.MinAlpha,[1 1 3])) = NaN;
        end

        function [rgb,alpha] = render(name)
            % The glyph NAME as colour (16x16x3, straight not premultiplied)
            % and coverage (16x16, 0..1).
            S = mabr.ui.Icon.Supersample;
            N = mabr.ui.Icon.Size;
            M = N*S;
            [X,Y] = meshgrid(((1:M)-0.5)/S);
            c = struct('R',zeros(M),'G',zeros(M),'B',zeros(M),'A',false(M));
            K = mabr.ui.Icon.Palette;

            % Shapes over this glyph's grid; each returns a coverage mask.
            Box  = @(r)       mabr.ui.Icon.box(X,Y,r);
            RBox = @(r,rad)   mabr.ui.Icon.rbox(X,Y,r,rad);
            Disc = @(p,r)     hypot(X-p(1),Y-p(2)) <= r;
            Ring = @(p,r0,r1) mabr.ui.Icon.annulus(X,Y,p,r0,r1);
            Line = @(P,w)     mabr.ui.Icon.polyline(X,Y,P,w);
            Poly = @(P)       inpolygon(X,Y,P(:,1),P(:,2));
            Arc  = @(p,r,w,a0,a1) mabr.ui.Icon.arc(X,Y,p,r,w,a0,a1);
            P    = @mabr.ui.Icon.paint;
            Cut  = @mabr.ui.Icon.cut;
            Bump = @mabr.ui.Icon.bump;

            switch name
                % ---------------------------------------------- main window
                case 'live'        % a monitor on a stand, a response on the
                                   % glass and the red dot of a recording
                    c = P(c,RBox([0 1 16 13],1.5),K.Ink);
                    c = P(c,RBox([1 2 15 12],0.8),K.Screen);
                    c = P(c,Box([6 13 10 14]),K.Ink);
                    c = P(c,RBox([3 14 13 15.5],0.5),K.Ink);
                    x = linspace(2,14,240);
                    t = (x-2)/12;
                    y = 8.5 - 1.2*Bump(t,0.20,0.035) + 0.6*Bump(t,0.30,0.035) ...
                            - 1.6*Bump(t,0.40,0.040) - 3.6*Bump(t,0.62,0.050) ...
                            + 1.8*Bump(t,0.76,0.060);
                    c = P(c,Line([x(:) y(:)],1.15),K.Phosphor);
                    c = P(c,Disc([12.5 4.5],1.4),K.Red);

                case 'metrics'     % a growth curve through measured points,
                                   % and a + because each press adds a window
                    c = P(c,Line([1.5 1.5; 1.5 14.5; 14.5 14.5],1.0),K.Ink);
                    f = @(x) 12.6 - 7.4./(1+exp(-(x-7.6)/1.3));
                    x = linspace(2.6,13.4,200);
                    c = P(c,Line([x(:) f(x(:))],1.2),K.Blue);
                    for xi = [3.6 7.6 11.6]
                        c = P(c,Disc([xi f(xi)],1.6),K.Orange);
                    end
                    c = Cut(c,Disc([12.5 3.5],4.3));
                    c = P(c,Disc([12.5 3.5],3.5),K.Green);
                    c = P(c,Box([12 1 13 6]) | Box([10 3 15 4]),K.Paper);

                case 'traces'      % a level series: the organizer's stack,
                                   % smaller and later as the level falls
                    base = [4.5 9.5 14.5];
                    amp  = [3.6 2.4 1.3];
                    col  = mabr.ui.Icon.Series;
                    x = linspace(0.5,15.5,240);
                    t = (x-0.5)/15;
                    for k = 1:3
                        lat = 0.34 + 0.07*(k-1);
                        y = base(k) - amp(k)*Bump(t,lat,0.06) + 0.45*amp(k)*Bump(t,lat+0.16,0.065);
                        c = P(c,Line([x(:) y(:)],1.3),col(k,:));
                    end

                case 'stim'        % a loudspeaker, sounding
                    c = P(c,RBox([1 5 5 11],0.6),K.Ink);
                    c = P(c,Poly([4 5; 8.5 1.5; 8.5 14.5; 4 11]),K.Ink);
                    c = P(c,Arc([8.6 8],2.9,1.35,-48,48),K.Orange);
                    c = P(c,Arc([8.6 8],5.7,1.35,-52,52),K.Orange);

                case 'progress'    % a gauge most of the way round
                    c = P(c,Ring([8 8],4.0,7.5),K.Track);
                    c = P(c,Arc([8 8],5.75,3.5,90-252,90),K.Green);

                case 'order'       % a play list: done, playing now, to come
                    c = P(c,Line([1.3 4.0; 3.0 5.7; 5.8 2.3],1.6),K.Green);
                    c = P(c,RBox([7 3 15 5],1.0),K.Grey);
                    c = P(c,Poly([1.5 5.2; 1.5 10.8; 6 8]),K.Orange);
                    c = P(c,RBox([7 7 15 9],1.0),K.Ink);
                    c = P(c,Ring([3.5 12.5],1.0,1.9),K.Grey);
                    c = P(c,RBox([7 11 15 13],1.0),K.Grey);

                case 'notes'       % a notepad, with the pencil writing on it
                    c = P(c,RBox([1 2 12 15],0.8),K.Ink);
                    c = P(c,Box([2 3 11 14]),K.Note);
                    for y = [6 8 10 12]
                        c = P(c,Box([3 y 10 y+1]),K.Ink*0.55 + 0.45*K.Note);
                    end
                    for x = [3 6 9]
                        c = P(c,RBox([x 0.5 x+1 4],0.5),K.Ink);
                    end
                    c = mabr.ui.Icon.pencil(c,X,Y,[15.4 4.6],[8.4 11.6],K);

                case 'front'       % windows piled up, one brought forward
                    c = mabr.ui.Icon.window(c,X,Y,[0 0 11 10],K.Grey,K.Paper,K.Grey);
                    c = Cut(c,Box([4 5 16 16]));
                    c = mabr.ui.Icon.window(c,X,Y,[5 6 16 16],K.Blue,K.Paper,K.Ink);

                case 'arrange'     % this window, the others tiled beside it
                    c = mabr.ui.Icon.window(c,X,Y,[0 1 7 16],K.Ink,K.Paper,K.Ink);
                    c = mabr.ui.Icon.window(c,X,Y,[8 1 16 8],K.Blue,K.Paper,K.Ink);
                    c = mabr.ui.Icon.window(c,X,Y,[8 9 16 16],K.Blue,K.Paper,K.Ink);

                case 'pin'         % a push pin, stuck in at an angle
                    u = [-1 1]/sqrt(2);  v = [1 1]/sqrt(2);  h = [10.9 5.1];
                    U = (X-h(1))*u(1) + (Y-h(2))*u(2);    % along the pin
                    V = (X-h(1))*v(1) + (Y-h(2))*v(2);    % across it
                    c = P(c,mabr.ui.Icon.box(U,V,[5.0 -0.6 11.6 0.6]),K.Ink);
                    c = P(c,mabr.ui.Icon.rbox(U,V,[3.4 -3.4 5.0 3.4],0.6),K.Red*0.8);
                    c = P(c,mabr.ui.Icon.box(U,V,[0.2 -1.6 3.6 1.6]),K.Red);
                    c = P(c,mabr.ui.Icon.rbox(U,V,[-2.1 -3.2 0.4 3.2],0.9),K.Red);
                    c = P(c,mabr.ui.Icon.rbox(U,V,[-1.5 -2.3 -0.5 0.2],0.4),K.Paper*0.75 + K.Red*0.25);

                case 'help'        % a question mark in a disc
                    c = P(c,Disc([8 8],7.5),K.Blue);
                    c = P(c,Arc([8 6],2.5,2.0,-62,195),K.Paper);
                    c = P(c,Line([9.17 8.21; 8 9.4],2.0) | Box([7 9.2 9 10.6]),K.Paper);
                    c = P(c,RBox([7 12 9 14],0.5),K.Paper);

                % -------------------------------------------- trace organizer
                case 'grow'        % one response, its scale pushed outward
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 11],8,5.2,K.Blue);
                    c = P(c,Box([13 3 14 13]),K.Orange);
                    c = P(c,Poly([13.5 0.2; 10.8 3.6; 16.2 3.6]),K.Orange);
                    c = P(c,Poly([13.5 15.8; 10.8 12.4; 16.2 12.4]),K.Orange);

                case 'shrink'      % one response, its scale pressed inward
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 11],8,2.2,K.Blue);
                    c = P(c,Box([13 0 14 4.6]) | Box([13 11.4 14 16]),K.Orange);
                    c = P(c,Poly([13.5 7.4; 10.8 4.0; 16.2 4.0]),K.Orange);
                    c = P(c,Poly([13.5 8.6; 10.8 12.0; 16.2 12.0]),K.Orange);

                case 'spread'      % two traces, pushed apart
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 15.5],2.5,1.6,K.Blue);
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 15.5],14.5,1.6,K.Blue);
                    c = P(c,Box([13 6.5 14 9.5]),K.Orange);
                    c = P(c,Poly([13.5 4.0; 10.8 7.0; 16.2 7.0]),K.Orange);
                    c = P(c,Poly([13.5 12.0; 10.8 9.0; 16.2 9.0]),K.Orange);

                case 'squeeze'     % two traces, pressed together
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 15.5],5.5,1.6,K.Blue);
                    c = mabr.ui.Icon.response(c,X,Y,[0.5 15.5],10.5,1.6,K.Blue);
                    c = P(c,Box([13 0 14 1]) | Box([13 15 14 16]),K.Orange);
                    c = P(c,Poly([13.5 4.2; 10.8 0.8; 16.2 0.8]),K.Orange);
                    c = P(c,Poly([13.5 11.8; 10.8 15.2; 16.2 15.2]),K.Orange);

                case 'peaks'       % markers dropped on a response's peaks
                    x = linspace(0.5,15.5,240);
                    t = (x-0.5)/15;
                    y = 12.5 - 2.4*Bump(t,0.24,0.045) + 0.8*Bump(t,0.36,0.05) ...
                             - 5.6*Bump(t,0.66,0.055) + 2.2*Bump(t,0.82,0.06);
                    c = P(c,Line([x(:) y(:)],1.2),K.Blue);
                    for xp = [0.24 0.66]*15 + 0.5
                        yp = interp1(x,y,xp);
                        c = P(c,Poly([xp-2.2 yp-5.0; xp+2.2 yp-5.0; xp yp-1.6]),K.Orange);
                    end

                case 'inspect'     % a magnifier over one response
                    g = [6.5 6.5];
                    c = P(c,Line([10.2 10.2; 14.6 14.6],2.8),K.Ink);
                    c = P(c,Disc(g,5.8),K.Ink);
                    c = P(c,Disc(g,4.5),K.Sky);
                    x = linspace(1.5,11.5,160);
                    t = (x-1.5)/10;
                    y = 7.3 - 3.4*Bump(t,0.45,0.08) + 1.6*Bump(t,0.65,0.08);
                    c = P(c,Line([x(:) y(:)],1.15) & Disc(g,4.5),K.Blue);

                case 'save'        % a floppy disk
                    c = P(c,Poly([1 1; 13 1; 15 3; 15 15; 1 15]),K.Blue);
                    c = P(c,Box([4 1 11 6]),K.Steel);
                    c = P(c,Box([8 2 10 5]),K.Blue);
                    c = P(c,RBox([3 8 13 15],0.5),K.Paper);
                    c = P(c,Box([4 10 12 11]) | Box([4 12 12 13]),K.Track);

                case 'load'        % a folder, opened
                    back = [0.5 2.5; 5.5 2.5; 7 4; 13.5 4; 13.5 14.5; 0.5 14.5];
                    c = P(c,Poly(back),K.FolderBk);
                    c = P(c,Box([2 5 12 12]),K.Paper);
                    flap = [3.6 7.4; 15.6 7.4; 13 14.6; 0.6 14.6];
                    c = P(c,Poly(flap),K.Folder);
                    c = P(c,Line([flap; flap(1,:)],0.8),K.FolderBk);

                case 'trash'       % a waste bin: removes everything
                    c = P(c,RBox([5 0 11 2.5],0.8),K.Ink);
                    c = Cut(c,Box([6.5 1 9.5 2]));
                    c = P(c,RBox([1 2 15 4],0.6),K.Ink);
                    c = P(c,Poly([2.5 5; 13.5 5; 12.5 16; 3.5 16]),K.Red);
                    c = P(c,Box([5 7 6 14]) | Box([10 7 11 14]) | Box([7.5 7 8.5 14]), ...
                        K.Paper*0.7 + K.Red*0.3);

                case 'keys'        % a keyboard, F1 lit: the shortcut list
                    c = P(c,RBox([0 3 16 12],1.2),K.Ink);
                    c = P(c,Box([1 4 15 11]),K.Paper);
                    for x = 2:2:12
                        c = P(c,Box([x 5 x+1 6]),K.Ink);
                    end
                    for x = 3:2:13
                        c = P(c,Box([x 7 x+1 8]),K.Ink);
                    end
                    c = P(c,Box([2 5 3 6]),K.Orange);
                    c = P(c,Box([4 9 12 10]),K.Ink);

                otherwise
                    error('mabr:ui:Icon:unknown','No icon named "%s".',name);
            end

            % Box-filter the supersampled canvas down to pixels. Colour is
            % averaged weighted by coverage (premultiplied, then divided
            % back out) so an edge pixel keeps its shape's colour rather
            % than fading toward black.
            blk = @(Z) squeeze(mean(mean(reshape(Z,S,N,S,N),1),3));
            a = double(c.A);
            alpha = blk(a);
            w = max(alpha,eps);
            rgb = cat(3,blk(c.R.*a)./w,blk(c.G.*a)./w,blk(c.B.*a)./w);
            rgb = min(max(rgb,0),1);
        end

        function img = sheet(names,scale,bg)
            % Every glyph in NAMES (default: all) side by side on BG, once
            % at 1x and once enlarged SCALE times (nearest neighbour, so
            % the pixels are the ones a toolbar shows). An RGB image.
            if nargin < 1 || isempty(names), names = mabr.ui.Icon.names(); end
            if nargin < 2 || isempty(scale), scale = 6; end
            if nargin < 3 || isempty(bg), bg = mabr.ui.Icon.Background; end
            N = mabr.ui.Icon.Size;
            gap = 4;
            cw = N*scale + 2*gap;                 % one glyph's column
            n = numel(names);
            img = repmat(reshape(bg,1,1,3),[N + 2*gap + cw, n*cw, 1]);
            for k = 1:n
                c = mabr.ui.Icon.toolbar(names{k},bg);
                m = ~isnan(c(:,:,1));
                c(isnan(c)) = 0;
                x0 = (k-1)*cw + gap + floor((N*scale - N)/2);
                img = mabr.ui.Icon.place(img,c,m,gap,x0);
                big = zeros(N*scale,N*scale,3);
                for ch = 1:3
                    big(:,:,ch) = kron(c(:,:,ch),ones(scale));
                end
                bm = kron(double(m),ones(scale)) > 0.5;
                img = mabr.ui.Icon.place(img,big,bm,N + 3*gap,(k-1)*cw + gap);
            end
        end

        function f = preview(scale)
            % Show sheet() in a figure: the only real test of a 16 px glyph
            % is looking at it.
            if nargin < 1, scale = 6; end
            names = mabr.ui.Icon.names();
            img = mabr.ui.Icon.sheet(names,scale);
            f = figure('Name','MABR toolbar icons','NumberTitle','off', ...
                'MenuBar','none','Color',mabr.ui.Icon.Background);
            ax = axes(f,'Position',[0 0.12 1 0.88]);
            mabr.ui.hideAxesToolbar(ax);
            image(ax,img);
            axis(ax,'image','off');
            cellW = size(img,2)/numel(names);
            for k = 1:numel(names)
                text(ax,(k-0.5)*cellW,size(img,1)+2,names{k}, ...
                    'HorizontalAlignment','center','VerticalAlignment','top', ...
                    'Interpreter','none','FontSize',8);
            end
        end
    end

    methods (Static, Access = private)
        function m = box(X,Y,r)
            % r = [x0 y0 x1 y1]
            m = X >= r(1) & X < r(3) & Y >= r(2) & Y < r(4);
        end

        function m = rbox(X,Y,r,rad)
            % A box with its corners rounded to radius RAD.
            dx = max(max(r(1)+rad - X, X - (r(3)-rad)),0);
            dy = max(max(r(2)+rad - Y, Y - (r(4)-rad)),0);
            m = mabr.ui.Icon.box(X,Y,r) & hypot(dx,dy) <= rad;
        end

        function m = annulus(X,Y,p,r0,r1)
            d = hypot(X-p(1),Y-p(2));
            m = d >= r0 & d <= r1;
        end

        function m = arc(X,Y,p,r,w,a0,a1)
            % A stroke of width W along the circle of radius R about P,
            % counter-clockwise (y up, degrees) from A0 to A1, round-capped.
            d = hypot(X-p(1),Y-p(2));
            ang = atan2d(-(Y-p(2)),X-p(1));
            in = mod(ang-a0,360) <= mod(a1-a0,360);
            m = in & abs(d-r) <= w/2;
            for a = [a0 a1]
                q = p + r*[cosd(a) -sind(a)];
                m = m | hypot(X-q(1),Y-q(2)) <= w/2;
            end
        end

        function m = polyline(X,Y,P,w)
            % Every point within W/2 of the polyline through the rows of P:
            % round joins and round caps.
            d = inf(size(X));
            for k = 1:size(P,1)-1
                d = min(d,mabr.ui.Icon.segDist(X,Y,P(k,:),P(k+1,:)));
            end
            m = d <= w/2;
        end

        function d = segDist(X,Y,a,b)
            ab = b - a;
            L2 = ab*ab.';
            if L2 == 0
                d = hypot(X-a(1),Y-a(2));
                return;
            end
            t = ((X-a(1))*ab(1) + (Y-a(2))*ab(2)) / L2;
            t = min(max(t,0),1);
            d = hypot(X-(a(1)+t*ab(1)),Y-(a(2)+t*ab(2)));
        end

        function y = bump(t,mu,sd)
            y = exp(-0.5*((t-mu)/sd).^2);
        end

        function c = paint(c,mask,rgb)
            % Lay RGB over MASK.
            c.R(mask) = rgb(1); c.G(mask) = rgb(2); c.B(mask) = rgb(3);
            c.A(mask) = true;
        end

        function c = cut(c,mask)
            % Clear MASK back to transparent: the gap that separates a shape
            % from whatever it is drawn over.
            c.A(mask) = false;
        end

        function c = window(c,X,Y,r,title,body,edge)
            % A window: a frame in EDGE, a two-pixel title bar in TITLE, and
            % BODY inside.
            c = mabr.ui.Icon.paint(c,mabr.ui.Icon.box(X,Y,r),edge);
            c = mabr.ui.Icon.paint(c,mabr.ui.Icon.box(X,Y,[r(1) r(2) r(3) r(2)+3]),title);
            c = mabr.ui.Icon.paint(c,mabr.ui.Icon.box(X,Y,[r(1)+1 r(2)+3 r(3)-1 r(4)-1]),body);
        end

        function c = response(c,X,Y,xr,base,amp,rgb)
            % An evoked response over XR on baseline BASE: a peak of height
            % AMP, then the trough after it.
            x = linspace(xr(1),xr(2),200);
            t = (x-xr(1))/(xr(2)-xr(1));
            y = base - amp*mabr.ui.Icon.bump(t,0.42,0.09) ...
                     + 0.4*amp*mabr.ui.Icon.bump(t,0.64,0.09);
            c = mabr.ui.Icon.paint(c,mabr.ui.Icon.polyline(X,Y,[x(:) y(:)],1.2),rgb);
        end

        function c = pencil(c,X,Y,a,b,K)
            % A pencil from its eraser end A to its point B, with a clear
            % margin cut around it so it reads over whatever is beneath.
            L = norm(b-a);
            u = (b-a)/L;  v = [-u(2) u(1)];
            U = (X-a(1))*u(1) + (Y-a(2))*u(2);
            V = (X-a(1))*v(1) + (Y-a(2))*v(2);
            hw = 1.35;
            tip = L - 3.0;
            body = U >= 0 & U <= tip & abs(V) <= hw;
            cone = U > tip & U <= L & abs(V) <= hw*(L-U)/3.0;
            c = mabr.ui.Icon.cut(c,(U >= -0.9 & U <= tip & abs(V) <= hw+0.9) | ...
                (U > tip & U <= L+0.9 & abs(V) <= hw*(L+0.9-U)/3.0 + 0.6));
            c = mabr.ui.Icon.paint(c,body,K.Orange);
            c = mabr.ui.Icon.paint(c,body & U <= 1.6,K.Eraser);
            c = mabr.ui.Icon.paint(c,body & U > 1.6 & U <= 2.4,K.Steel);
            c = mabr.ui.Icon.paint(c,cone,K.Wood);
            c = mabr.ui.Icon.paint(c,cone & U > L-1.2,K.Ink);
        end

        function img = place(img,src,mask,r0,c0)
            % Copy SRC into IMG at row R0, column C0 (0-based offsets)
            % where MASK is true.
            [h,w,~] = size(src);
            rows = r0 + (1:h);  cols = c0 + (1:w);
            for ch = 1:3
                dst = img(rows,cols,ch);
                s = src(:,:,ch);
                dst(mask) = s(mask);
                img(rows,cols,ch) = dst;
            end
        end
    end
end
