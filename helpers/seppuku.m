function seppuku
% matlab doesn't always fully close using exit

id  = feature('getpid');
if ispc
  Cmd = sprintf('Taskkill /PID %d /F',id);
elseif (ismac || isunix)
  Cmd = sprintf('kill -9 %d',id);
else
  disp('unknown operating system');
end
system(Cmd);