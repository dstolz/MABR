function keypressed = ismousedpressed()

% 0 no button is pressed
% 1 is left button
% 2 is right button
% 3 is scroll button push (not scrolling)

keypressed = 0;
if libisloaded('user32')
    left = calllib('user32','GetAsyncKeyState',int32(1)) ~= 0;
    right = calllib('user32','GetAsyncKeyState',int32(2)) ~= 0;
    scroll = calllib('user32','GetAsyncKeyState',int32(4)) ~= 0;
    keypressed = max([1 2 3].*double([left right scroll]));
end

end