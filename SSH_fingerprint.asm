
; ASCII z sumy kontrolnej klucza
; + ruchy wiezy, jezeli 1. arg to 1
; Agnieszka Pulnar

data segment
	
	no_args			db      "Blad: nie podano argumentow.$"
	not_en 			db 		"Blad: podano za malo argumentow. Odpowiednia ilosc: 2.$"	
	too_many		db 		"Blad: podano za duzo argumentow. Odpowiednia ilosc: 2.$"
	a1_bad 			db 		"Blad: pierwszy argument jest nieprawidlowy. Dopuszczalny jest jeden znak: 0/1.$"	
	a2_bad			db		"Blad: klucz jest nieprawidlowy. Poprawny zapis w kodzie szesnastkowym to 32 znaki a-f, 0-9.$"
	
	
	buf				db 		150 dup ('$')				; tablica na dane wejsciowe, maks 150 znakow parametrow
	num_of_args 	db		0h							; liczba wprowadzonych argumentow
	which_vers		db		?							; flaga w ktorej wersji ma pracowac program - oryginalnej czy z modyfikacja (oryginalna 30h - '0' w tabeli ASCII, 
														; zmodyfikowana 31h - '1' w tabeli ASCII)
														
	key				db		16 dup (?)					; tablica na 16 bajtow przekonwertowanego klucza 
	
	chessboard		db		153 dup	(0)					; tabela przechowujaca info o polach 'szachownicy', ktore bedzie odwiedzac goniec/wieza - 
														; liczba odwiedzin (na poczatku 0) -> konkretne znaczki z tabeli 'symbols'
														; 17 kolumn * 9 wersow
	

	symbols 		db 		' ','.','o','+','=','*','B','O','X','@','%','&','#','/','^'			; tabela symboli oznaczajacych liczbe odwiedzin pola
	finish			db		?							; pole, na ktorym zakonczy wedrowke figura (0-152d)
	
	top 			db 		"+--[ RSA 1024]----+$"		; elementy do narysowania ASCII arta, top sie zepsul
	crlf			db		10d, 13d, '$'				; 10d - LF (koniec linii), 13d - CR (powrot karetki)
	end_of_fgp		db 		"+-----------------+$"	
	top2 			db 		"+--[ RSA 1024]----+$"
	statement		db		"ASCII-art tego klucza wyglada tak:$"
	
	args_offsets	db 		20 dup (?)					; tabele: offsetow, dlugosci argumentow									
	args_lengths	db 		20 dup (?)														
	input_bytes 	db 		?							; liczba bajtow wprowadzonych w linii komend								
	
data ends


code segment

	start:
		assume cs:code, ds:data, ss:sstack 
		
		mov ax,seg stack_ptr							; przygotowanie stosu
		mov ss,ax		
		mov sp,offset stack_ptr	

		mov ax, seg data								; bohater mojego parsera!!
		mov ds, ax
		
		call read										; wywolanie funkcji
		call check_args
		call convert_to_bin
		call go_thru_bytes
		call fingerprint
		call show_fingerprint
		call end_of_prog

; ===== PARSER =====

	; ===== 1. WCZYTAJ ARGUMENTY =====
    ; pobiera znaki z linii komend, sprawdza czy bialy i zjada biale, zapisuje parametry w tabicy argumentow 'buf', jesli brak argumentow -> alert, 
	; zlicza argumenty -> num_of_args, wypelnia tablice offsetow (pierwszych znakow) argumentow (args_offsets) oraz tablice dlugosci kolejnych argumentow (args_lengths)
	
	read proc	
		push ax								; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic (przy .286 mozna tez pusha i popa, wtedy jeszcze sp i bp)
		push bx																		
		push cx																		
		push dx																		
		push di																		
		push si		
		
		xor ax, ax							; czyszcze rejestry, ktore za chwile wykorzystam
		xor bx, bx
		xor cx, cx
		xor di, di																
		xor si, si																															
	
		mov bl, byte ptr es:[80h]			; do bl kopiuje liczbe znakow w linii komend - PSP: 80h (ile znakow podalismy w linii komend)
											; 81h (spacja), 82h (od niego kolejno wprowadzone argumenty)
		cmp bl, 1h																
		jb alert_no_args					; jesli mamy mniej niz 1 znak, to nie podano argumentow -> komunikat i wyjscie										
	
		; wpp -> przechwytujemy argumnty do przygotowanej tablicy
		
		mov si, offset buf					; ustawiam offset na tablice na argumenty (=lea si,buf - mniej optymalne, do obliczen!), znak -> si								
		mov cx, offset args_offsets			; umieszczam w cx offset tablicy offsetow argumentow 
		
		dec bx								; bx - liczba bajtow/znakow z linii komend
											; dekrementuje, by pominac spacje pod offsetem 81h
		mov word ptr ds:[input_bytes], bx	; otrzymana liczbe bajtow zapisuje do przygotowanej zmiennej 										

		mov al, byte ptr es:[82h]			; pierwszy znak z linii komend -> al											
		call check_if_white					; sprawdz, czy jest bialym znakiem							
		cmp ah, 0h							; flaga: 0=nie bialy, 1=bialy -> trzeba go zjesc
		je get_the_char						; jesli znak nie jest bialy, przetwarzamy go 
		; jne -> zjedz bialy znak
		
		
		eat:								; dla bialego znaku
			call eat_it								; lec po bialych znakach dopoki nie napotkasz nie bialego, di - licznik sprawdzonych znakow 								
			cmp di, word ptr ds:[input_bytes]		; czy sprawdzilismy juz wszystkie wprowadzone znaki?										
			je finish_parsing						; jesli tak, konczymy 
			
		get_the_char:						; dla pierwszego nie bialego znaku po bialych (pierwszego znaku nowego argumentu)									
			push bx
			push dx
			push di	
			
			push ax
			
			mov di, cx							; teraz di -  wskaznik kolejnego wolnego miejsca w tablicy offsetow																			
			mov word ptr ds:[di], si			; zapisz offset tego argumentu w tablicy offsetow 										
			add cx, 2h							; przy kolejnym wywolaniu zwieksz wskaznik tablicy args_offsets o 16 bitow, czyli dlugosc kolejnego offsetu 												
			inc num_of_args						; inkrementuj liczbe argumentow 								
			xor dl, dl							; wyzeruj licznik dlugosci argumentu, bo bedziemy go przegladac 									
				
			pop ax																		
			pop di
				
			characters:								; przetwarzaj nowy argument 
				mov byte ptr ds:[si], al			; zapisz nie bialy znak do tablicy argumentow 								
				inc dl								; dl - licznik dlugosci aktualnego argumentu - zwiekszamy 									
				inc di								; di - licznik znakow z linii komend - zwiekszamy (przeskocz na kolejny znak z linii komend)				
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?																
				je fin								; jesli tak, konczymy 									

				inc si								; wpp -> przesuwamy wskaznik w tablicy argumentow													
				mov al, byte ptr es:[82h + di]		; pobierz kolejny znak z linii komend									
				xor ah, ah							; zerujemy ah -> flaga
				call check_if_white														
				cmp ah, 0h							; jesli kolejny znak nie jest bialy, dalej iterujemy po argumencie 									
			je characters																
			; wpp (koniec argumentu):
			
			fin:	
				push di																	
				inc si								; przesun wskaznik w tablicy argumentow - rozdzielamy argumenty dolarami																
				mov di, offset args_lengths									
				mov ax, word ptr ds:[num_of_args]	; numer ostatniego argumentu -> ax																									
				add di, ax		
				dec di								; di wskazywal wczesniej na 1. argument 
				mov byte ptr ds:[di], dl			; zapisz dlugosc ostatniego argumentu								
				pop di
				pop dx
				pop bx	
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?																
		jne eat										; jesli nie, jedz biale znaki dopoki nie trafisz na kolejny arg 							
			
		jmp finish_parsing
		
		check_if_white proc				; otrzymuje znak w al, sprawdzam, czy znak jest bialy 
			xor ah, ah					; zeruje, w ah ustawie za chwile flage - 1=bialy, 0=nie bialy
			cmp al, 20h					; 20h - spacja w tabeli ASCII									
			je white																		
			cmp al, 9h					; 9h - tabulator w tabeli ASCII												
			je white															
			ret		
			
			white:
				mov ah, 1h		; ustawiam flage														
				ret
		check_if_white endp
		
		eat_it proc						; otrzymuje w di licznik sprawdzonych znakow 																				
			push bx
			
			its_white:
				inc di								; inkrementujemy liczbe sprawdzonych znakow (bialy, wiec pomijamy) 															
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?													
				je exit								; jesli tak, konczymy 							
				mov al, byte ptr es:[82h + di]		; wpp: pobieramy do akumulatora nastepny znak z linii komend					
				xor ah, ah							; zerujemy ah -> ustawimy flage			
				call check_if_white															
				cmp ah, 1h															
			je its_white							; jesli bialy, jedz dalej, dopoki nie napotkasz nie bialego 
			
			exit:
				pop bx
				ret
		eat_it endp
		
		alert_no_args:
			mov ax, seg no_args
			mov ds, ax
			mov dx, offset no_args
			mov ah, 9h							; funkcja int 21,9 wypisuje odpowiedni komunikat z ds:dx, konczymy
			int 21h
			pop si
			pop di
			pop dx
			pop cx
			pop bx
			call end_of_prog
			
			finish_parsing:
				pop si				; przywracam pierwotne wartosci rejestrow
				pop di
				pop dx
				pop cx
				pop bx
				pop ax
				ret
		
	read endp


	; ===== 2. SPRAWDZ POPRAWNOSC ARGUMENTOW =====
	; sprawdza, czy wpowadzone argumenty sa poprawne: czy sa dokladnie 2, czy 1. ma dlugosc 1 i czy sklada sie z 0 lub 1, czy 2. ma dlugosc 32 i czy ma odpowiednie znaki... 
	; zamienia znaki z klucza na wlasciwe cyfry szesnastkowe
	
	check_args proc			
		push di				; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
		push si	
		push bx
		push cx
		push dx
		
		; czy wprowadzono prawidlowa liczbe argumentow?
		mov al, num_of_args
		cmp al, 2h																									
		jb not_enough			; jezli mniej niz 2, to za malo
		ja tumany				; jesli wiecej niz 2, to za duzo
			
		; czy argument 1. (indeks 0. w tablicy) ma dlugosc 1?													
		mov di, offset args_lengths														
		mov ah, byte ptr ds:[di]														
		cmp ah, 1h					; dlugosc 1. parametru -> ah												
		jne ar1						; jesli rozna od 1, to argument niepoprawny
			
		; czy argument 1. sklada sie z 0 lub 1?											
		mov si, offset args_offsets														
		mov di, word ptr ds:[si]	; do di zaladuj offset 1. argumentu,  czyli domniemanej flafgi											
		mov al, byte ptr ds:[di]	; pierwszy parametr -> al											
		cmp al, 30h					; 30h = kod '0' w tabeli ASCII											
		jb ar1						; jesli kod "mniejszy niz 0", to argument jest niepoprawny
		cmp al, 31h					; 31h = kod '1' w tabeli ASCII
		ja ar1						; jesli kod "wiekszy niz 1", jw.								
			
		; czy argument 2. (indeks 1. w tablicy) ma dlugosc 32?
		mov di, offset args_lengths				
		inc di																											
		mov ah, byte ptr ds:[di]	; dlugosc 2. parametru -> ah													
		cmp ah, 32d																
		jne ar2						; jesli rozna od 32, to argument niepoprawny						
			
		; czy argument 2. sklada sie z odpowiednich znakow?
		mov si, word ptr offset args_offsets														
		mov di, word ptr ds:[si+2]	; offset 2. arg. -> di											
		dec di						; zmniejszam di o 1, zeby nie pominac 1. znaku w 1. przbiegu petli										
		xor cx,cx					; zerujemy cx: bedzie licznikiem - mamy 32 znaki do sprawdzenia										
			
			go_thru_key:
				inc di				; przesun wskaznik na kolejny znak											
				inc cx				; sprawdzilismy kolejny znak -> inkrementujemy licznik												
				
				mov al, byte ptr ds:[di]		; zaladuj do al kolejny znak klucza										
				cmp al, 30h						; 30h =  kod '0'	w tabeli ASCII
				jb ar2							; jesli kod znaku "mniejszy niz 0", to klucz niepoprawny							
				cmp al, 39h						; 39h = kod '9' w tabeli ASCII												
				jbe from_0_to_9																
				cmp al, 61h						; 61h = kod 'a' w tabeli ASCII									
				jb ar2							; jesli kod "mniejszy niz a", to klucz niepoprawny					
				cmp al, 66h						; 66h = kod 'f' w tabeli ASCII								
				ja ar2							; jesli kod "wiekszy niz f", jw.
				
				from_a_to_f:					; zapisz litere z klucza w postaci szesnastkowej nie-ASCII
					mov al, 61h					; 61h = kod 'a' w ASCII					
					sub byte ptr ds:[di], al	; aby otrzymac cyfre szesnastkowa <10,15>, musimy od jej kodu ASCII odjac kod 'a' i dodac 10
					add byte ptr ds:[di], 0ah
					cmp cx, 32d					; czy przeszlismy juz przez wszystkie 32 znaki?
			jb go_thru_key						; jesli nie, przegladaj dalej
			
				from_0_to_9:					; zapisz cyfre z klucza w postaci szesnastkowej nie-ASCII
					mov al, 30h					
					sub byte ptr ds:[di], al	; aby uzyskac cyfre, od ich kodu ASCII odejmujemy kod '0'=30h
					cmp cx, 32d		  			; czy przeszlismy juz przez wszystkie 32 znaki?
			jb go_thru_key						; jesli nie, przegladaj dalej
				
		jmp exit						; mamy 32 znaki -> zakoncz sprawdzanie
			
			not_enough:					; komunikat gdy za malo arg.
				mov ax, seg not_en
				mov ds, ax
				mov dx, offset not_en
				jmp alert_exit
			
			tumany:						; komunikat gdy za duzo arg.
				mov ax, seg too_many
				mov ds, ax
				mov dx, offset too_many
				jmp alert_exit
				
			ar1:						; komunikat o nieprawidlowym argumencie 1.
				mov ax, seg a1_bad
				mov ds, ax
				mov dx, offset a1_bad
				jmp alert_exit
				
			ar2:						; komunikat o nieprawidlowym argumencie 2.
				mov ax, seg a2_bad
				mov ds, ax
				mov dx, offset a2_bad 
				jmp alert_exit
			
			alert_exit:					; wypisz komunikat i zakoncz 															
				mov ah,9																
				int 21h																	
				call end_of_prog														
		exit:
		pop dx							; przywracam pierwotne wartosci rejestrow
		pop cx
		pop bx
		pop si
		pop di
		ret
	check_args endp
	
; ===== UTWORZ FINGERPRINT =====
		
		; ===== 3. KONWERTUJ CIAG BAJTOW W ZAPISIE HEKSADECYMALNYM -> POSTAĆ BINARNA =====
		; opracowuje tabele key zawierajaca postac binarna klucza, laczy 4-bitowe cyfry heksadecymalne w 16 par
		
		convert_to_bin proc																
			push ax					; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
			push cx
			push dx
			push si
			push di
			
			call which_version		; sprawdz, w ktorej wersji ma pracowac program
			
			mov si, word ptr offset args_offsets													
			mov di, word ptr ds:[si+2]		; w di umieszczam offset 2. argumentu, czyli klucza, ktory konwertujemy											
			mov si, offset key				; w si umieszczam offset tablicy na zapis binarny konwertowanego klucza
				
			mov cx, 16d						; mamy 16 bajtow do przekonwertowania (32 cyfry hex* 4 bity)
				
			convert_pair:
				mov al, byte ptr ds:[di]	; pobierz pierwsza 4-bitowa cyfre z pary																								
				push cx						; zachowaj wartosc licznika z petli
				mov cl, 4h																		
				rol al, cl					; rotuj zawartosc al o 4 w lewo, a puste miejsca wypelnij "0" z przodu = shl al, cl										
				pop cx						; przywroc licznik z petli
				mov dl, al					; al -> dl			
				inc di 
				mov al, byte ptr ds:[di]	; do al pobierz druga cyfre z pary																								
				add al, dl					; dodaj do siebie obie cyfry -> mamy bajt											
				mov byte ptr ds:[si], al	; umiesc w tablicy binarnego klucza 	
				inc di 
				inc si																
			loop convert_pair		
					
			pop di					 ; przywracam pierwotne wartosci rejestrow
			pop si
			pop dx
			pop cx
			pop ax
			ret
		convert_to_bin endp
		
		; ===== 4. SPRAWDZ, W JAKIEJ WERSJI MA PRACOWAC PROGRAM =====
		; w zmiennej which_vers okresla precyzyjnie, czy program ma dzialac normalnie (ruchy gonca), czy w wersji zmodyfikowanej (ruchy wiezy)
		
		which_version proc
			mov si, word ptr offset args_offsets	; pobierz offset 1. parametru 													
			mov di, word ptr ds:[si]														
			mov al, byte ptr ds:[di]				; rzutuj typ
			mov byte ptr ds:[which_vers], al		; w zmiennej-fladze ustaw, ktora wersje programu mamy wykonac:
													; (oryginalna 30h - '0' w tabeli ASCII, zmodyfikowana 31h - '1' w tabeli ASCII)
			ret
		which_version endp

		
		; ===== 5. ANALIZUJ BITY -> RUCHY NA SZACHOWNICY =====
		; przejmuje po kolei od prawej po bicie pary bitow (00, 01, 10 lub 11) i na ich podstawie okresla ruch gonca lub wiezy
		; ruchy gonca: 00 - w lewo i w gore, 01 - w prawo i w gore, 10 - w lewo i w dol, 11 - w prawo i w dol
		; ruchy wiezy: 00 - w gore, 01 - w prawo, 10 - w lewo, 11 - w dol (przesuniete o 45* zgodnie z ruchem wskazowek zegara)
		
		go_thru_bytes proc															
			push di									; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
			push dx
			push si
			push cx
			push bx
				
				mov di, offset key					; przygotuj przekonwertowany klucz									
				mov si, 76d							; si - pozycja na szachownicy - startujemy na srodku planszy, czyli polu nr 76									
				mov cx, 16d							; mamy do przebiegniecia 16 bajtow klucza, cx bedzie licznikiem -> 0										
				mov al, byte ptr ds:[which_vers]	; w ktorej wersji ma dzialac program?
				cmp al, 31h																
				je rook																	
				
				bishop:								; standardowa wersja programu z ruchami gonca														
					mov bl, byte ptr ds:[di]		; wez pare bitow								
					push cx				
					mov cx, 4h						; kazdy z 16 bajtow klucza zawiera 4 pary bitow, cx po raz kolejny licznikiem, wiec wczesniej pushujemy
					
					b_move:															
						push dx
						shr bl, 1h					; przesuniecie bitow w prawo -> do cf wedruje mlodszy bit z pary:
						jc right?					; _1 - w prawo i ?, _0 - w lewo i ?
						jnc left? 
	
						right?:						; _1
							call go_right
							shr bl, 1h				; kolejne przesuniecie bitow w prawo -> do cf wedruje bit odpowiedzialny za ruch gora-dol
							jc down					; 11 - w prawo i w gore
							jnc up					; 01 - w prawo i w dol
							
						left?:						; _0
							call go_left			
							shr bl, 1h				; kolejne przesuniecie bitow w prawo -> do cf wedruje bit odpowiedzialny za ruch gora-dol
							jc down					; 10 - w lewo i w dol
							jnc up					; 00 - w lewo i w gore
							
						up: 
							call go_up
							jmp move_n_fin1
								
						down:
							call go_down
							jmp move_n_fin1
							
						move_n_fin1:
						call MOVE
						pop dx
																		
					loop b_move		
					
					pop cx	
					inc di							; przesun wskaznik na nastepna pare
				loop bishop		
				
				jmp exit																	
				
				rook:								; zmodyfikowana wersja programu - ruchy wiezy															
					mov bl, byte ptr ds:[di]		; wez pare bitow							
					push cx
					mov cx, 4h						; kazdy z 16 bajtow klucza zawiera 4 pary bitow, cx po raz kolejny licznikiem, wiec wczesniej pushujemy
					
					r_move:
						push dx
						shr bl, 1h					; przesuniecie bitow w prawo -> do cf wedruje mlodszy bit z pary:																														
						jnc up?left					; _0 : 00 -> w górę, 10 -> w lewo, a wiec nalezy sprawdzic drugi bit
						jc down?right				; _1 : 11 -> w dół, 01 -> w prawo, a wiec nalezy sprawdzic drugi bit 
								
						down?right:
							shr bl, 1h				; kolejne przesuniecie bitow w prawo -> drugi bit dopelnia info o kierunku ruchu											
							jc r_down				; 11 - w dol										
							jnc r_right				; 01 - w prawo											
							
						up?left:													
							shr bl, 1h				; kolejne przesuniecie bitow w prawo -> drugi bit dopelnia info o kierunku ruchu																
							jc r_left				; 10 - w lewo 									
							jnc r_up				; 00 - w gore													
								
							r_right:
								call go_right															
								jmp move_n_fin2											
							r_up:
								call go_up																
								jmp move_n_fin2											
							r_down:
								call go_down															
								jmp move_n_fin2											
							r_left:
								call go_left															
								jmp move_n_fin2											
								
							move_n_fin2:
							call MOVE																
							pop dx		
							
						loop r_move	
						
					pop cx
					inc di							; przesun wskaznik na nastepna pare 
				loop rook	

				jmp exit
				
			exit:
				mov word ptr ds:[finish], si	; zapisz koncowa pozycje figury w odpowiedniej zmiennej												
				pop bx							; przywracam pierwotne wartosci rejestrow
				pop cx
				pop si
				pop dx
				pop di
				ret
		go_thru_bytes endp

		; === 5a. >>> RUCH W PRAWO <<< === 
		; przesuwa figure o 1 w prawo
		go_right proc
			push dx						; mlodsza czesc dx wykorzystamy przy dzieleniu
			mov ax, si					; w ax umiesc aktualna pozycje na szachownicy (jej numer 0-152)														
			mov dl, 17d																
			div dl						; DIV ax/dl = al r. ah											
			cmp ah, 16d													
			je exit						; jesli reszta z dzielenia jest rowna 16, to znaczy ze jestesmy przy prawej krawedzi, czyli dalej nie mozemy sie ruszyc	-> wychodzimy			
			inc si						; wpp -> przesuwamy o 1 w prawo, czyli dodajemy 1 do licznika aktualnej pozycji i tez wychodzimy
			
			exit:
				pop dx 
				ret
		go_right endp
		
		; === 5b. >>>>> RUCH W LEWO <<<<< === 
		; przesuwa figure o 1 w lewo 
		go_left proc
			push dx						; mlodsza czesc dx wykorzystamy przy dzieleniu
			mov ax, si					; w ax umiesc aktualna pozycje na szachownicy										
			mov dl, 17d															
			div dl						; DIV ax/dl = al r. ah												
			cmp ah, 0h					; jesli reszta z dzielenia jest rowna 0, to znaczy ze jestesmy przy lewj krawedzi, czyli dalej nie mozemy sie ruszyc	-> wychodzimy										
			je exit																
			dec si						; wpp -> przesuwamy o 1 w lewo, czyli odejmujemy 1 od licznika aktualnej pozycji i tez wychodzimy
			
			exit:
				pop dx
				ret
		go_left endp
		
		; === 5c. >>> RUCH W GORE <<< ===
		go_up proc
			cmp si, 16d																
			jbe exit1					; jesli figura znajduje sie na polu 0-16, to nie moze juz isc w gore -> wychodzimy									
			sub si, 17d					; wpp -> przesuwamy o rzad, czyli 17 pól do tylu, a wiec odejmujemy 17 od licznika aktualnej poz i tez wychodzimy
				
			exit1:
				ret
		go_up endp

		; === 5d. >>> RUCH W DOL <<< ===
		go_down proc
			cmp si, 136d															 			
			jae exit1					; jesli figura znajduje sie na polu 136-152, to nie moze juz isc w dol -> wychodzimy											
			add si, 17d					; wpp -> przesuwamy o rzad, czyli 17 pól do przodu, a wiec dodajemy 17 do licznika aktualnej poz i tez wychodzimy
			
			exit1:
				ret	
		go_down endp
				
		; === 5e. Wykonaj ruch ===
		; inkrementuje licznik odwiedzonego w wyniku powyzszego ruchu pola
		MOVE proc
			push di
			push ax
			
			mov di, offset chessboard	; przygotuj adres szachownicy						
			add di, si					; adr. tabl. przesuwamy o aktualna pozycje po wykonaniu ruchow z pary bitow									
			inc byte ptr ds:[di]		; zwiekszamy wartosc licznika w odpowiednim polu szachownicy	
			
			pop ax
			pop di
			ret
		MOVE endp
		

		; ===== 6. GENERUJ FINGERPRINT =====
		; zamienia liczniki w poszczegolnych komorkach tablicy=szachownicy na okreslone znaki do wygenerowania fingerprinta
		
		fingerprint proc																
				push cx								; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
				push si
				push di
				push ax
				
				mov cx, 153d						; musimy wygenerowac symbol dla kazdego z 153 potencjalnie odwiedzonych pol szachownicy
				mov si, offset chessboard			; przygotuj szachownice (jej offset)
				push si
				mov di, offset symbols				; przygotuj tablice znakow do wypelniania szachownicy (jej offset)
				
				nums_into_chars:
					push di							; zachowuje offset tablicy symboli na pozniej, bo bede go modyfikowac
					xor ax, ax
					mov al, byte ptr ds:[si]		; pobierz do al liczbe odwiedzin dla kolejnego pola
					cmp al, 14d					
					jbe upto14						; jesli liczba odwiedzin <= 14, to przepisujemy znaczek z tabelki
					mov al, 14d						; a jesli > 14, to postepujemy jak dla 14 odwiedzin
					upto14:
						add di, ax					; do poczatku tablicy wklejanych znakow dodajemy liczbe odwiedzin pola o offsecie si,
													;  									dzieki czemu dostajemy sie do konkretnego znaku
						mov ah, byte ptr ds:[di]	; znaczek -> ah
						mov byte ptr ds:[si], ah	; ah -> odpowiednie miejsce na szachownicy
						inc si						; przesun wskaznik na kolejne pole
					pop di							; wroc do poczatku tablicy znaczkow
				loop nums_into_chars
				
				pop si								; do si ponownie trafia offset szachownicy
				mov byte ptr ds:[si+76d], 53h		; w srodkowym polu umiesc znaczek startu (53h = "S' w tabeli ASCII)
				mov di, word ptr ds:[finish];
				add si, di							; do offsetu szachownicy dodaj offset ostatniego polozenia figury
				mov byte ptr ds:[si], 45h			; umiesc tam znaczek konca (45h = "E" w tabeli ASCII)
		
				pop ax							 	; przywracam pierwotne wartosci rejestrow
				pop di
				pop si
				pop cx
			ret
		fingerprint endp

		
		; ===== 7. RYSUJ FINGERPRINT =====
		; "dzieli" jednowymiarowa tablice="szachownice" na 9 wersow po 17 znakow, wypisujac na ekranie stworzona grafike ASCII, dodaje ramki
		
		show_fingerprint proc
				push si						; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
				push cx
				push dx
				push ax
				
				mov dx, offset crlf			; nowa linia (int 21,9 wypisuje zawartosc ds:dx)
				mov ah, 9h
				int 21h
				mov dx, offset statement	; wypisz tekst powitalny
				;mov ah, 9h
				int 21h
				mov dx, offset crlf			; nowa linia
				;mov ah, 9h
				int 21h
				mov dx, offset top2			; wypisz gorna ramke
				;mov ah, 9h
				int 21h
				mov dx, offset crlf			; przejdz do nowej linii -> zaczynamy wypisywanie "zawartosci" szachownicy
				;mov ah, 9h
				int 21h
				
				mov si, offset chessboard
				mov cx, 9h					; cx bedzie licznikiem - mamy 9 linii do wypisania
				print_line_by_line:
					push cx					; we wnetrzu petli odkladam cx na stos, bo po raz kolejny wykorzystam go jako licznik -
					mov cx, 17d				; mamy bowiem 17 znakow do wypisania w kazdej linii
					mov dl, '|'				; lewy przeg szachownicy
					mov ah, 2h				; int 21,2 wypisuje ZNAK umieszczony w dl
					int 21h
					print_line:
						mov dl,  byte ptr ds:[si] ; wypisz znak po znaku cala linie symboli szachownicy
						inc si
						;mov ah, 2h
						int 21h
					loop print_line
					
					mov dl, '|'				; wypisz prawy brzeg
					;mov ah, 2h
					int 21h
					mov dx, offset crlf		; przejdz do nowej linii
					mov ah, 9h
					int 21h
					pop cx
				loop print_line_by_line
				
				mov dx, offset end_of_fgp	; wypisz dolna ramke
				mov ah, 9h
				int 21h
				
				mov dx, offset crlf			;  nowa linia
				;mov ah, 9h
				int 21h
				
				pop ax					 	; przywracam pierwotne wartosci rejestrow
				pop dx
				pop cx
				pop si
				ret
		show_fingerprint endp
			

		; ===== KONIEC PROGRAMU =====
		end_of_prog proc
			mov	ah, 4ch			; koniec, powrot do DOS - int 21,4c -> terminate process
			int	21h
			ret
		end_of_prog endp 

	code ends

sstack segment stack
	dw 150 dup (?)				; stos o rozmiarze 150 slow
	stack_ptr dw ?
sstack ends

end start
