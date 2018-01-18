    -module(chat).
    -export([listen/1]).
	-compile(export_all).


	crearanillo1(N) ->
		S = lists:flatten(io_lib:format("~p", [N])),
		Work = string:concat("worker", S),
		register(list_to_atom(Work), self()),
		workers(crearanillo(N-1, self()), N).

	crearanillo(0, P) ->
		Pid = spawn(?MODULE, workers, [P,0]),
		register(worker0, Pid),
		Pid;
	
	crearanillo(N, P) ->
		S = lists:flatten(io_lib:format("~p", [N])),
		Work = string:concat("worker",S),
		Pid = spawn(?MODULE, workers, [crearanillo(N-1,P),N]),
		register(list_to_atom(Work),Pid),
		Pid.

    % Iniciamos el dispatcher
    listen(Port) ->
		%LANZARWORKERS
		register(cnt,spawn(?MODULE, loop1,[0])),
		register(cnt_error,spawn(?MODULE, loop1,[1])),
		register(conectados,spawn(?MODULE, conectados,[])),
		io:format("cnt: ~p, cnt_error: ~p, conectados: ~p ~n",[whereis(cnt),whereis(cnt_error),whereis(conectados)]),
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
			{ok, "CON\r\n"} ->
						IDw = IDc rem 5,
						S = lists:flatten(io_lib:format("~p", [IDw])),
						S2 = string:concat("OK ID ",S),
						gen_tcp:send(Socket, S2 ++"\r\n" ++  [0]),
						gen_tcp:send(Socket, "Ingrese su nombre:" ++ [0]),
						{ok,Name1} = gen_tcp:recv(Socket,0),
						Argaux = string:tokens(Name1, "\r"), 
						Name0 = lists:nth(1, Argaux),
						Name = Name0 ++ " ",
						conectados!{Name},
						io:format("Coneccion aceptada Cliente ID ~p Worker ID ~p ~n", [IDc,IDw]),
						gen_tcp:send(Socket,"OK\n" ++[0]),
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
						1000 -> Num_error = lists:flatten(io_lib:format("~p", [get_count(cnt_error)])),
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
	
	conectados() ->
	Buff = [],
	recv_con(Buff).
	
	recv_con(Buff) ->
	io:format("Buff: ~p ~n",[Buff]),
	receive
		{Name} -> BuffNew = lists:append(Buff, [Name]), %agregamos el nuevo cliente al buffer
				 io:format("Agregamos un cliente ~n"),
				 recv_con(BuffNew);
		{Pid,work} -> Pid!{Buff},
					  recv_con(Buff);
			A -> A=A,
				 recv_con(Buff)
					
				 
	end.
	
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	tochar(N) -> lists:flatten(io_lib:format("~p ", [N])).
	 	
		 
	workers(Sig, IDw) -> 
    receive
		{Data, Pid,IDc} -> case string:tokens(Data, " ") of
							["LSC\r\n"] -> conectados!{self(),work},
										   receive
												{Buff} -> Pid!{"OK " ++ Buff ++ [0] ++ ["\n"]}
										   end,
										   workers(Sig, IDw); 
							["CHAT","ID",Arg] -> Arg=Arg,
												 ok;
										C -> io:format("C ~n"),
										     C=C,
										     IDc=IDc,
											 workers(Sig, IDw)
							end;
				B -> io:format("B ~n"),
				     B=B,
					 workers(Sig, IDw)
	end.	

  %%%%%%%%%%%% WAIT %%%%%%%%%%%%%%%%%%%

  wait (Mili) -> 	receive
				after Mili -> ok
				end.

  %%%%%%%%%%%% FLUSH %%%%%%%%%%%%%%%%%%%
		
  flush() ->
	unregister(cnt),
	unregister(cnt_error),
	unregister(conectados),
	unregister(worker0),
	unregister(worker1),
	unregister(worker2),
	unregister(worker3),
    unregister(worker4).
