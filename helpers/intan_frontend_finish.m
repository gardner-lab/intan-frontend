function intan_frontend_finish(FILE,MOVE_DIR)
%
%
%

try
	movefile(FILE,MOVE_DIR);
    disp('Files relocated to '+MOVE_DIR);
catch
	disp('Could not move file: '+FILE);
	fclose('all');
end
