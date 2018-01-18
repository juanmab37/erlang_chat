    -module(serverErlang).
    -export([listen/1]).
	-compile(export_all).


	crearanillo1(N) ->
		Abiertos = [],
		Buff = [], %Ejemplo {"a.txt","txto"}
		S = lists:flatten(io_lib:format("~p", [N])),
		Work = string:concat("worker", S),
		register(list_to_atom(Work), self()),
		workers(Buff, crearanillo(N-1, self()), N, Abiertos).

	crearanillo(0, P) ->
		Abiertos = [],
		Buff = [],
		Pid = spawn(?MODULE, workers, [Buff,P,0,Abiertos]),
		register(worker0, Pid),
		Pid;
	
	crearanillo(N, P) ->
		Abiertos = [],
	    Buff = [],
		S = lists:flatten(io_lib:format("~p", [N])),
		Work = string:concat("worker",S),
		Pid = spawn(?MODULE, workers, [Buff,crearanillo(N-1,P),N,Abiertos]),
		register(list_to_atom(Work),Pid),
		Pid.

    % Iniciamos el dispatcher
    listen(Port) ->
		%LANZARWORKERS
		register(cnt,spawn(?MODULE, loop1,[0])),
		register(cnt_error,spawn(?MODULE, loop1,[1])),
		spawn(?MODULE, crearanillo1, [4]),
        {ok, LSocket} = gen_tcp:listen(Port,[{packet, 0}, {active, false}, list]),
        spawn(fun() -> accept(LSocket,0) end).

    % Esperamos a los clientes
    accept(LSocket, IDc) ->
        {ok, Socket} = gen_tcp:accept(LSocket),
        IDcNew = IDc + 1,
        Pid = spawn(?MODULE,clientes, [Socket,IDcNew]),
        gen_tcp:controlling_process(Socket, Pid),
        accept(LSocket,IDcNew).
					
	
	clientes(Socket, IDc) ->
		case gen_tcp:recv(Socket,0) of
			{ok, "CON\r\nLSD\r\n"} ->
						IDw = IDc rem 5,
						S = lists:flatten(io_lib:format("~p", [IDw])),
						S2 = string:concat("OK ID ",S),
						gen_tcp:send(Socket, S2 ++"\r\n" ++  [0]),
						io:format("Coneccion aceptada Cliente ID ~p Worker ID ~p ~n", [IDc,IDw]),
						loop(Socket,IDw,IDc),
						ok;
			{ok,"BYE\r\n"} -> gen_tcp:send(Socket,"OK "++[0]);													
			{ok,Data} -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
						 incr(cnt_error),
						 io:format("~p ~n",[Data]),
						 gen_tcp:send(Socket,"ERROR " ++ [Num_error] ++  " EBADCMD\n" ++[0]),%gen_tcp:send(Socket,"Error "++ Data ++", enviar CON para conectar\r\n "++[0]),
						 Data = Data,
						 clientes(Socket,IDc)
			end.
	
  loop(Socket,IDw,IDc) -> 
	case gen_tcp:recv(Socket,0) of
		{ok,"BYE\r\n"} -> S = lists:flatten(io_lib:format("~p", [IDw])),
						  Work = string:concat("worker",S),
					      list_to_atom(Work)!{"CLOSE",self(),IDc},
					      gen_tcp:send(Socket,"OK "++[0]);
		{ok, Data} -> S = lists:flatten(io_lib:format("~p", [IDw])),
					  Work = string:concat("worker",S),
					  list_to_atom(Work)!{Data,self(),IDc},
					  receive 
						{Resp} -> gen_tcp:send(Socket,Resp)
						
					  %%%%%%%%%%%%%%% SISTEMA TOLERANTE A FALLAS %%%%%%%%%%%%%%%%
					  after
						100 -> 	Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
								incr(cnt_error),
								Resp = "ERROR " ++ [Num_error] ++ " ETIME \n",
								gen_tcp:send(Socket,Resp)
					  end,
					  loop(Socket,IDw,IDc)
	end.
		
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	%%%%%%%%%%%%%%%%%%%%%% CONTADOR %%%%%%%%%%%%%%%%%%%%%%%
	
	loop1(Count) ->                            
    receive                                   
        { incr } -> 
            loop1(Count + 1);             
        { report, To } ->                    
            To ! { count, Count },            
            loop1(Count)                           
    end.                                     
 

	incr(Counter) -> Counter ! { incr }.
	
	get_count(Counter) ->
		 Counter ! { report, self() },
		 receive
			{ count, Count } -> Count
		 end.
		 
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

 
		 
	workers(Buff, Sig, IDw, Abiertos) -> 
    io:format("Buff ~p Abiertos ~p ~n", [Buff, Abiertos]),
		receive
			
			%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		
			{1, "LSD", BuffAcum} ->	BuffNew = lists:append(Buff, BuffAcum),
									Sig!{respls, BuffNew},
									workers(Buff, Sig, IDw,Abiertos);	
									
			{N, "LSD", BuffAcum} -> BuffNew = lists:append(Buff, BuffAcum),
									Sig!{N - 1, "LSD", BuffNew},
									workers(Buff, Sig, IDw, Abiertos);
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

			
			{1, "Chequeo", Arg, Pid} ->  D = lists:keymember(Arg, 3, Abiertos),
									  if
									   (not D) -> Pid!{["False"]},
												  workers(Buff, Sig, IDw,Abiertos);
										D -> Pid!{["True"]},
											 workers(Buff, Sig, IDw,Abiertos)
									  end;
			
			{N, "Chequeo", Arg, Pid} ->  D = lists:keymember(Arg, 3, Abiertos),
									  if
									   (not D) -> Sig!{N-1,"Chequeo",Arg,Pid},
												  workers(Buff, Sig, IDw,Abiertos);
										D -> Pid!{["True"]},
											 workers(Buff, Sig, IDw,Abiertos)
									  end;
									
			{1, "DEL", Arg, Pid} -> 	C = lists:keymember(Arg, 1, Buff),
										if
											C -> 	Pid!{"OK" ++ [0] ++ ["\n"]},
													workers(lists:keydelete(Arg,1, Buff), Sig, IDw, Abiertos);
											true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
													incr(cnt_error),
													Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
													workers(Buff, Sig, IDw,Abiertos)
										end;
									
			{N, "DEL", Arg, Pid} -> 	C = lists:keymember(Arg, 1, Buff),
										if
											C -> 	Pid!{"OK" ++ [0] ++ ["\n"]},
													workers(lists:keydelete(Arg,1, Buff), Sig, IDw,Abiertos);
											true -> Sig!{N - 1, "DEL", Arg, Pid}, 
													workers(Buff, Sig, IDw, Abiertos)
										end;
									
			%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			
			{1, "OPN", Arg, Pid, MiPid} ->   C = lists:keymember(Arg, 1, Buff),
											 if
													 C ->  NFD = get_count(cnt),
														   incr(cnt),
														   Pid!{"OK FD " ++[lists:flatten(io_lib:format("~p", [NFD]))] ++[0] ++ ["\n"]},
														   MiPid!{NFD,self()},
						                                   workers(Buff,Sig,IDw,Abiertos);
						                              
						                        (not C)->  MiPid!{"ERROR"},
														   workers(Buff,Sig,IDw,Abiertos)
											 end;
			{N, "OPN", Arg, Pid, MiPid} ->   C = lists:keymember(Arg, 1, Buff),
											     if
														C ->  NFD = get_count(cnt),
															  incr(cnt),
															  Pid!{"OK FD " ++[lists:flatten(io_lib:format("~p", [NFD]))] ++[0] ++ ["\n"]},
						                                      MiPid!{NFD,self()},
						                                      workers(Buff,Sig,IDw,Abiertos);
						                            
						                          (not C) ->  Sig!{N-1, "OPN",Arg,Pid,MiPid},
																 workers(Buff,Sig,IDw,Abiertos)
						                     end;
			%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			
			{"WRT", Arg, Msj, Pid} -> Aux = element(2,element(2,lists:keysearch(Arg,1,Buff))), %lo ya escrito
								   Buffnew = lists:keyreplace(Arg,1,Buff,{Arg,Aux ++ Msj}), 
								   Pid!{"OK" ++ [0] ++ ["\n"]},
								   workers(Buffnew,Sig,IDw,Abiertos);
			
			%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			
			{"REA",Arg,Arg1,MiPid,Yaleido} -> Aux = element(2,element(2,lists:keysearch(Arg,1,Buff))),
											if
												length(Aux) >= Arg1 ->  Rta = lists:sublist(Aux,Yaleido+1,Arg1),
																	    LongRta = lists:flatten(io_lib:format("~p", [length(Rta)])),
																	    MiPid!{"OK SIZE " ++ LongRta ++ [" "] ++ Rta ++ [0] ++ ["\n"],Yaleido+Arg1},
																	    workers(Buff,Sig,IDw,Abiertos);
															    true -> MiPid!{"OK SIZE " ++ ["0"] ++ [] ++ [0] ++ ["\n"],Yaleido},
																   	    workers(Buff,Sig,IDw,Abiertos)
											end;
			
			%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			
			{Data, Pid,IDc} -> case string:tokens(Data, " ") of	
                            ["CLOSE"] -> NewAbiertos = [], 
										 workers(Buff, Sig, IDw, NewAbiertos);
							
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%			 
                              
							["LSD\r\n"] ->	Sig!{4, "LSD", Buff},
											receive {respls, BuffFinal} -> Rta = lists:map(fun(P) -> element(1, P) ++ " " end , BuffFinal)  end,
											Pid!{"OK " ++ lists:append(Rta) ++ [0] ++ ["\n"]},
											workers(Buff, Sig, IDw, Abiertos);
				
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
									   
							["DEL", Arg0] -> Argaux = string:tokens(Arg0, "\r"), 
											
											% Chequeamos que no esté abierto
											D = lists:keymember(lists:nth(1, Argaux), 3, Abiertos),
											if
											  % Caso en que no está abierto
											  % Le preguntamos a los demás workers si ellos lo tienen abiertos
											  (not D) -> Sig!{4, "Chequeo", lists:nth(1, Argaux),self()},
														 receive
															{T} -> case T of
															        % Caso en que no está abierto en ningun worker
																	["False"] -> C = lists:keymember(lists:nth(1, Argaux), 1, Buff),
																			   if
																				 C -> Pid!{"OK" ++ [0] ++ ["\n"]}, 
																					 workers(lists:keydelete(lists:nth(1, Argaux),1, Buff), Sig, IDw, Abiertos);
																			  true -> Sig!{4, "DEL", lists:nth(1, Argaux), Pid}, 
																					 workers(Buff, Sig, IDw, Abiertos)
																			   end;
																	% Caso en que está abierto en algún worker
															        ["True"] -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																			  incr(cnt_error),
																			  Pid!{"ERROR "++ [Num_error] ++ [" EOPNFILE"] ++ [0] ++ ["\n"]}, 
																			  workers(Buff, Sig, IDw, Abiertos)
																	end
														 end;
												% Caso en que está abierto		
												true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
													    incr(cnt_error),
														Pid!{"ERROR "++ [Num_error] ++ [" EOPNFILE"] ++ [0] ++ ["\n"]}, 
														workers(Buff, Sig, IDw, Abiertos)
											end;
																	
											
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%				
																		
							["CRE", Arg0] -> Argaux = string:tokens(Arg0, "\r"), % NO PERMITE CREAR NOMBRES CON ESPACIOS!
							
											 % Buscamos en los buffers de los demás workers si el archivo ya está creado o no
											 Sig!{4, "LSD", Buff},
										     receive {respls, BuffFinal} ->  C = lists:keymember(lists:nth(1, Argaux), 1, BuffFinal) end,
											 if
												% Caso en que el archivo ya está creado
												C -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
													 incr(cnt_error),
													 Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
													 workers(Buff, Sig, IDw, Abiertos);
												% Caso en que el archivo no está creado, entonces procedemos... (se lo agregamos)
												true -> Pid!{"OK" ++ [0] ++ ["\n"]},
														workers(Buff ++ [{lists:nth(1, Argaux),""}], Sig, IDw, Abiertos)
											 end;
											 
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%				 
											 
							["OPN", Arg0] -> Argaux = string:tokens(Arg0, "\r"), 
											 Arg = lists:nth(1, Argaux),
											 C = lists:keymember(Arg, 1, Buff),
											 D = lists:keymember(Arg, 3, Abiertos),
											 if
											   (C and (not D)) ->  NFD = get_count(cnt),
																	incr(cnt),
																    Pid!{"OK FD " ++[lists:flatten(io_lib:format("~p", [NFD]))] ++[0] ++ ["\n"]},
																    Abiertos2 = Abiertos ++ [{IDc,NFD,Arg,self(),0}],
						                                            workers(Buff,Sig,IDw,Abiertos2);
						                                      D ->  E = (IDc == element(1,(element(2,lists:keysearch(Arg,3,Abiertos)))) ),
																   if
																	       E -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																				incr(cnt_error),
																				Pid!{"ERROR "++ [Num_error] ++ [" EOPNFILE"] ++ [0] ++ ["\n"]}, 
																                workers(Buff,Sig,IDw,Abiertos);
																	C and (not E) -> NFD = get_count(cnt),
																					  incr(cnt),
																					  Pid!{"OK FD " ++[lists:flatten(io_lib:format("~p", [NFD]))] ++[0] ++ ["\n"]},
																					  Abiertos2 = Abiertos ++ [{IDc,NFD,Arg,self(),0}],
																					  workers(Buff,Sig,IDw,Abiertos2);
																	(not C) and (not E) ->	Sig!{4, "OPN",Arg,Pid,self()},
																							receive {NFD,PidAbridor} -> Abiertos2 = Abiertos ++ [{IDc,NFD,Arg,PidAbridor,0}],
																														 workers(Buff,Sig,IDw,Abiertos2); 
																											{"ERROR"} -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																														 incr(cnt_error),
																														 Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
																														 workers(Buff,Sig,IDw,Abiertos)
																							end	  
														           
														           end; 
						                  
																
						                                 true ->  Sig!{4, "OPN",Arg,Pid,self()},
																  receive {NFD,PidAbridor} -> Abiertos2 = Abiertos ++ [{IDc,NFD,Arg,PidAbridor,0}],
																					   		   workers(Buff,Sig,IDw,Abiertos2); 
																		          {"ERROR"} -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																							   incr(cnt_error),
																							   Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
																					           workers(Buff,Sig,IDw,Abiertos)
																  end
																 
						                     end;
						               
						    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%                 
						   
							["REA","FD",Arg0,"SIZE",Arg1] -> B3  = (error /= element(1,string:to_integer(Arg0))) and (error /= element(1,string:to_integer(Arg1))),
															 B2 = (0 =< element(1,string:to_integer(Arg1))) and (0 =< element(1,string:to_integer(Arg0))), 
															 if
																B2 and B3-> C = lists:keymember(element(1,string:to_integer(Arg0)), 2, Abiertos),
																			if
																			   C -> Argaux = element(2,lists:keysearch(element(1,string:to_integer(Arg0)),2,Abiertos)),
																					D = (IDc == element(1,Argaux)),
																					if
																					  D -> Arg = element(3,Argaux),
																						   Yaleido = element(5,Argaux),
																						   E = (self() == element(4,Argaux) ),
																						   if
																							 E -> Aux = element(2,element(2,lists:keysearch(Arg,1,Buff))),
																								  Arg1b = element(1,string:to_integer(lists:nth(1,string:tokens(Arg1,"\r")))),
																								  %io:format("~p ~p -~p- ~n",[length(Aux),Arg1b,Yaleido]),
																								  if
																									(length(Aux) >= Arg1b + Yaleido) ->	Rta = lists:sublist(Aux,Yaleido+1,Arg1b),
																																		Abiertos2 = lists:keyreplace(Arg,3,Abiertos,{IDc,element(2,Argaux),Arg,self(),Yaleido+Arg1b}),
																																		io:format("~p ~n",[Rta]),
																																		LongRta = lists:flatten(io_lib:format("~p", [length(Rta)])),
																																		Pid!{"OK SIZE " ++ LongRta ++ [" "] ++ Rta ++ [0] ++ ["\n"]},
																																		workers(Buff,Sig,IDw,Abiertos2);
																											true -> Pid!{"OK SIZE " ++ ["0"] ++ [] ++ [0] ++ ["\n"]},
																													workers(Buff,Sig,IDw,Abiertos)
																								  end;
																							 true -> Arg1b = element(1,string:to_integer(lists:nth(1,string:tokens(Arg1,"\r")))),
																									 element(4,Argaux)!{"REA",Arg,Arg1b,self(),Yaleido},
																									 receive
																										{Resp,Yaleido2} -> Pid!{Resp},
																														   if
																															 Yaleido2 /= Yaleido -> Abiertos2 = lists:keyreplace(Arg,3,Abiertos,{IDc,element(2,Argaux),Arg,element(4,Argaux),Yaleido2}),
																																					workers(Buff,Sig,IDw,Abiertos2);
																																			true -> workers(Buff,Sig,IDw,Abiertos)
																														   end
																									 end,	
																									 workers(Buff,Sig,IDw,Abiertos)
																							end;
																					  true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																							  incr(cnt_error),
																							  Pid!{"ERROR "++ [Num_error] ++ [" EBADFD"] ++ [0] ++ ["\n"]}, 
																							  workers(Buff,Sig,IDw,Abiertos) 	
																					 end;
																				true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																						incr(cnt_error),
																						Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
																						workers(Buff,Sig,IDw,Abiertos)	
																			  end;
															true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																	  incr(cnt_error),
																	  Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
																      workers(Buff,Sig,IDw,Abiertos)
																      
														 end;				
														 
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%							 
														 
							["CLO","FD",Arg0] ->  Argaux = string:tokens(Arg0,"\r"), 
												  % Buscamos su NFD
												  NFD = element(1,string:to_integer(lists:nth(1, Argaux))),io:format("~p ~n",[NFD]),
												  % Vemos si el archivo verdaderamente está abierto
												  C = lists:keymember(NFD, 2, Abiertos),
												  if
												    % Caso en que está abierto
													C -> Pid!{"OK" ++ [0] ++ ["\n"]}, 
														 Arg = element(3,element(2,lists:keysearch(NFD,2,Abiertos))),
														 workers(Buff, Sig, IDw, lists:keydelete(Arg,3, Abiertos));
													% Caso en que no está abierto
													true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
															incr(cnt_error),
															Pid!{"ERROR "++ [Num_error] ++ [" EBADFD"] ++ [0] ++ ["\n"]}, 
															workers(Buff, Sig, IDw, Abiertos)
												  end;	
							
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
							
							B -> if
									(length(B) > 5) ->	B2 = ("WRT" == lists:nth(1, B)) and ("FD" == lists:nth(2, B)) and ("SIZE" == lists:nth(4, B)),
														B3 = (error /= element(1,string:to_integer(lists:nth(3, B)))) and (error /= element(1,string:to_integer(lists:nth(5, B)))),
														B4 = (0 =< element(1,string:to_integer(lists:nth(3, B)))) and (0 =< element(1,string:to_integer(lists:nth(5, B)))),
														%io:format("~p ~p ~n",[B2,B3]),
														 if
															B2 and B3 and B4 -> Arg2aux = element(2,lists:split(5,B)),
																 Arg2 = lists:nth(1, string:tokens(string:join(Arg2aux," "), "\r")),
																 Arg1 = lists:nth(5, B),
																 Arg0 = lists:nth(3, B),
																 
																 C = lists:keymember(element(1,string:to_integer(Arg0)), 2, Abiertos),
																 if
																	C -> Argaux = element(2,lists:keysearch(element(1,string:to_integer(Arg0)),2,Abiertos)),
																		 D = (IDc == element(1,Argaux)),
																		 if
																			D -> Msj = lists:sublist(Arg2,element(1,string:to_integer(Arg1))),%lists:nth(1,string:tokens(Arg2, "\r")),
																				 Arg = element(3,Argaux),
																				 E = (self() == element(4,Argaux) ),
																				 if
																					E -> Aux = element(2,element(2,lists:keysearch(Arg,1,Buff))), %lo ya escrito
																						 Buffnew = lists:keyreplace(Arg,1,Buff,{Arg,Aux ++ Msj}), 
																						 Pid!{"OK" ++ [0] ++ ["\n"]},
																						 workers(Buffnew,Sig,IDw,Abiertos);
																					true -> element(4,Argaux)!{"WRT",Arg,Msj,Pid},
																							workers(Buff,Sig,IDw,Abiertos)
																				 end;
																			true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																					incr(cnt_error),
																					Pid!{"ERROR "++ [Num_error] ++ [" EBADFD"] ++ [0] ++ ["\n"]}, 
																					workers(Buff,Sig,IDw,Abiertos)
																		 end;
																	 true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																			 incr(cnt_error),
																			 Pid!{"ERROR "++ [Num_error] ++ [" EBADFD"] ++ [0] ++ ["\n"]}, 
																			 workers(Buff,Sig,IDw,Abiertos)
																  end;
															  true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
																	  incr(cnt_error),
																	  Pid!{"ERROR "++ [Num_error] ++ [" EBADARG"] ++ [0] ++ ["\n"]}, 
																      workers(Buff,Sig,IDw,Abiertos)
															end;
											true -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
													incr(cnt_error),
													Pid!{"ERROR "++ [Num_error] ++ [" EBADCMD"] ++ [0] ++ ["\n"]}, 
													workers(Buff,Sig,IDw,Abiertos)
									end
									
							%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%		
							end
		
		
		end.

  %%%%%%%%%%%% WAIT %%%%%%%%%%%%%%%%%%%

  wait (Mili) -> 	receive
				after Mili -> ok
				end.

  %%%%%%%%%%%% FLUSH %%%%%%%%%%%%%%%%%%%
		
  flush() ->
	unregister(cnt),
	unregister(cnt_error),
	unregister(worker0),
	unregister(worker1),
	unregister(worker2),
	unregister(worker3),
    unregister(worker4).
