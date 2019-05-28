function timer_Start(T,event,app)


% setup live plot
ax = app.live_plot;
figure(ancestor(ax,'figure'));

axa = app.live_analysis_plot;
figure(ancestor(axa,'figure'));
app.ABR.playrec(app,ax,axa);