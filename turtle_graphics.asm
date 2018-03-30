.286		; pusha i popa 
.387		; dla fpu 

data segment
	; dane dla parsera
	buf			db 		150 dup ('$')				; tablica na dane wejsciowe, maks 150 znakow parametrow
	num_of_args 		db		0h						; liczba wprowadzonych argumentow
	args_offsets		db 		20 dup (?)					; tablice: offsetow, dlugosci argumentow									
	args_lengths		db 		20 dup (?)														
	input_bytes 		db 		0h							; liczba bajtow wprowadzonych w linii komend	
	iternum			db		?
	len				db 		?
	no_args			db      "Blad: nie podano argumentow.$"
	not_en 			db 		"Blad: podano za malo argumentow. Odpowiednia ilosc: 2.$"	
	too_many		db 		"Blad: podano za duzo argumentow. Odpowiednia ilosc: 2.$"
	iternum_len		db		"Blad: pierwszy argument (liczba iteracji 1-systemu) powinien byc liczba calkowita z przedzialu [1; 4].$"
	len_len			db		"Blad: drugi argument (dlugosc pojedynczego odcinka krzywej) powinien byc liczba calkowita z przedzialu [1; 25].$"
	string			db		2048 dup ('$') 		; przy maksymalnie 4 iteracjach max dlugosc lancucha znakow to 1792:
												; Nr iter.	| Liczba liter	| Liczba "F"
												;    1.		| 	   28		|	  12
												;	 2. 	|	   112		|	  48
												; 	 3.		| 	   448		|     192
												;	 4.		|	   1792		|     768
	intx			dw		20
	inty			dw		20
	three 			dw		3d 
	ten 			db		10d
data ends

code segment

	start:
		assume cs:code, ds:data, ss:stack 
		
		mov ax, seg stack_ptr							; przygotowanie stosu
		mov ss, ax		
		mov sp, offset stack_ptr	

		mov ax, seg data								; bohater mojego parsera!!
		mov ds, ax
		
		call read										; wywolanie funkcji
		call check_args
		call generate_string
		
		mov ax, 13h		; tryb graficzny 13h 320x200, 256 kolorow
		int 10h
		
		; ekran w trybie graficznym mieści się w segmencie 0A000h
		mov ax, 0A000h
		mov es, ax
		
		call FPU_setup
		call generate_Koch
		
		xor ax, ax	; ah = 0 -> czeka na wcisniecie dowolnego klawisza 
		int 16h
		
		mov ax, 3d	; wyjscie z trybu graficznego -> powrot do tradycyjnego trybu tekstowego 
		int 10h
		
		call end_of_prog

; ===== PARSER =====
	; ===== 1. WCZYTAJ ARGUMENTY =====
    ; pobiera znaki z linii komend, sprawdza czy bialy i zjada biale, zapisuje parametry w tabicy argumentow 'buf', jesli brak argumentow -> alert, 
	; zlicza argumenty -> num_of_args, wypelnia tablice offsetow (pierwszych znakow) argumentow (args_offsets) oraz tablice dlugosci kolejnych argumentow (args_lengths)
	read proc	
		pusha
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
			popa
			call end_of_prog
			
			finish_parsing:
				popa
				ret
	read endp
	
	; ===== 2. SPRAWDZ POPRAWNOSC ARGUMENTOW =====
	; sprawdza, czy wprowadzono dokladnie 2 argumenty, czy pierwszy (iternum) nalezy do przedzialu [1; 4], czy drugi nalezy do przedzialu [1; 25]
	; jesli nie -> error, komunikat 
	check_args proc			
		pusha				; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
		
		; czy wprowadzono prawidlowa liczbe argumentow?
		mov al, num_of_args
		cmp al, 2h																									
		jb not_enough			; jesli mniej niz 2, to za malo
		ja tumany				; jesli wiecej niz 2, to za duzo
			
		; czy argument 1. to cyfra z przedzialu [1; 4]?											
		mov di, offset args_lengths														
		mov ah, byte ptr ds:[di]		; dlugosc 1. parametru -> ah													
		cmp ah, 1d																
		jne wronglen_iternum			; jesli nie jest jednocyfrowy -> nieprawidlowy 
		mov si, offset args_offsets														
		mov di, word ptr ds:[si]											
		mov al, byte ptr ds:[di]		; kod 1-znakowego 1. parametru -> al
		sub al, 48d						; 48d = kod '0' w tabeli ASCII
		cmp al, 1d						; mamy teraz wlasciwa cyfre - jesli < 1, to niewlasciwa
		jb wronglen_iternum
		cmp al, 4d						; jesli > 4, to niewlasciwa
		ja wronglen_iternum
		mov ds:[iternum], al			; jesli 1. parametr wlasciwy, zapisujemy go w zmiennej "iternum"
		
		; czy argument 2. to liczba z przedzialu [1; 25]?
		mov di, offset args_lengths				
		inc di																											
		mov ah, byte ptr ds:[di]	; dlugosc 2. parametru -> ah	
		cmp ah, 2d
		ja wronglen_len				; jesli jest liczba wiecej niz 2-cyfrowa -> za dlugi 
		jb one_digit				; jesli jest 1-cyfrowy -> sprawdz jego poprawnosc 
		mov si, word ptr offset args_offsets														
		mov di, word ptr ds:[si+2]	; offset 2. arg. -> di		
		mov al, byte ptr ds:[di]	; al <- 1. znak 2. arg.
		sub al, 48d					; al := wlasciwa cyfra (nie w kodzie ASCII
		cmp al, 2d
		ja wronglen_len				; 2. parametr typu >= 3_ : za duzy 
		; jesli jest ok:
		mov ah, 10d
		mul ah						; MUL: ax = al*10
		mov ah, byte ptr ds:[di+1]	; ah <- 2. znak 2. arg.
		sub ah, 48d					; ah := wlasciwa cyfra (nie w kodzie ASCII)
		add al, ah 					; al := wlasciwa 2-cyfrowa liczba odpowiadajaca argumentowi "len"
		cmp al, 25d					
		ja wronglen_len
		mov ds:[len], al			; jesli 2. parametr wlasciwy, zapisujemy go w zmiennej "len"
		jmp exit
		
		one_digit:
			mov si, word ptr offset args_offsets														
			mov di, word ptr ds:[si+2]	; offset 2. arg. -> di		
			mov al, byte ptr ds:[di]	; jednoznakowy 2. arg -> al
			sub al, 48d			
			cmp al, 1d			
			jb wronglen_iternum			; jesli nie należy do cyfr ze zbioru {1, 2, ..., 9} (czyli jest 0), to niewlasciwa dlugosc
			mov ds:[len], al			; jesli 1. parametr wlasciwy, zapisujemy go w zmiennej "iternum"
		jmp exit
		
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
			
			wronglen_iternum:			; komunikat, gdy 1. arg. niewlasciwy
				mov ax, seg iternum_len
				mov ds, ax
				mov dx, offset iternum_len
				jmp alert_exit
				
			wronglen_len:				; komunikat, gdy 2. arg. niewlasciwy 
				mov ax, seg len_len
				mov ds, ax
				mov dx, offset len_len
				jmp alert_exit
			
			alert_exit:					; wypisz komunikat i zakoncz 															
				mov ah, 9h																
				int 21h																	
				call end_of_prog	
		exit:
		popa							; przywracam pierwotne wartosci rejestrow
		ret
	check_args endp
	
	; ===== 3. GENERUJ KOD SCIEZKI ====
	; rekurencyjnie tworzy napis, wg ktorego bedzie sie poruszac nasz zolw
	; zaczynamy od "F++F++F", przy kolejnej iteracji kazde "F" -> "F-F++F-F"	
	generate_string proc
		pusha
		
		mov di, offset string
		
		xor cx, cx
		mov cl, byte ptr ds:[iternum]	; cx - licznik iteracji 
		
		call recursive_insert  		; "F++F++F"
		mov al, '+'		
		mov byte ptr ds:[di], al
		inc di
		mov byte ptr ds:[di], al
		inc di
		call recursive_insert
		mov al, '+'
		mov byte ptr ds:[di], al
		inc di
		mov byte ptr ds:[di], al
		inc di
		call recursive_insert
		
		jmp gs_exit
		
		recursive_insert:
			jcxz finish 			; jesli zaglebilismy sie rekursywnie do ostatniej iteracji, to konczymy, wstawiajac "F" i wracamy do miejsca poprzedniego wywolania : CX==0 to warunek konca rekurencji 
			dec cx					; wywolania rekurencyjne z (cx-1)
			call recursive_insert	; "F-F++F-F"
			mov al, '-'
			mov byte ptr ds:[di], al
			inc di
			call recursive_insert
			mov al, '+'
			mov byte ptr ds:[di], al
			inc di
			mov byte ptr ds:[di], al
			inc di
			call recursive_insert
			mov al, '-'
			mov byte ptr ds:[di], al
			inc di
			call recursive_insert
			inc cx					; wracamy 
		ret 
		
		finish:
			mov al,'F'				; jesli zaglebilismy sie rekursywnie do ostatniej iteracji, to konczymy, wstawiajac "F" i wracamy do miejsca poprzedniego wywolania
			mov byte ptr ds:[di], al
			inc di
			ret 
	
		gs_exit:
			popa
			ret
	generate_string endp
	
	; ==== 4. INICJALIZACJA STOSU KOPROCESORA ====
	FPU_setup proc
		finit				; inicjalizacja koprocesora 
		fldpi				; laduje PI na szczyt stosu : st(0) = PI
		fidiv ds:[three]	; st = st/komorka -> st(0) = (PI)/3 = 60*
		fldz				; laduje 0 na szczyt stosu (nasz kąt)
		fild word ptr ds:[inty]	; laduje na stos liczbe calkowita - poczatkowe polozenie "na osi y"
		fild word ptr ds:[intx]									  ; poczatkowe polozenie "na osi y"
		; AKTUALNA ZAWARTOSC STOSU : [x, y, kąt, PI/3]	
		ret
	FPU_setup endp 
	
	; ===== 5. NA PODSTAWIE KODU TWÓRZ GRAFIKĘ ŻÓŁWIA =====
	; biegnie po kolei po znakach utworzonego kodu i w zaleznosci czy aktualnie badany znak to '+', '-' czy 'F',
	; modyfikuje kat ustawienia zolwia lub go porusza 
	generate_Koch proc
		pusha 
	
		mov si, offset string
		
		gK_loop:
			mov al, byte ptr ds:[si]
			inc si 
			cmp al, '$'		; '$' - koniec tablicy "string", sprawdzilismy juz wszystkie znaki naszego kodu 
			je gK_exit
			
			cmp al, 'F'
			je F_letter
			cmp al, '+'
			je plus
			cmp al, '-'
			je minus
		jmp gK_loop
		
		jmp gK_exit

		F_letter:
			call move_turtle
			jmp gK_loop			; kontynuuj bieganie po znakach 
		plus:
			; '+' oznacza zmiane kierunku zolwia o 60* zgodnie z ruchem wskazowek zegara
			; ZWIEKSZAMY wiec zmienna 'kąt' o 60 stopni (PI/3)
			; AKTUALNA ZAWARTOSC STOSU: [x, y, kąt, PI/3]
			fxch st(2)			; zamien st(0) z st(2) : AKTUALNA ZAWARTOSC STOSU: [kąt, y, x, PI/3]
			fadd st(0), st(3)	; dodaj do st(0) st(3) : AKTUALNA ZAWARTOSC STOSU: [kąt + PI/3, y, x, PI/3]
			fxch st(2)			; ponownie zamien miejscami st(0) z st(2) : AKTUALNA ZAWARTOSC STOSU: [x, y, kąt + PI/3, PI/3]
			; AKTUALNA ZAWARTOSC STOSU: [x, y, kąt + PI/3, PI/3]
			jmp gK_loop			; kontynuuj bieganie po znakach 
		minus:
			; '-' oznacza zmiane kierunku zolwia o 60* przeciwnie do ruchu wskazowek zegara
			; ZMNIEJSZAMY wiec zmienna 'kąt' o 60 stopni (PI/3)
			; AKTUALNA ZAWARTOSC STOSU: [x, y, kąt, PI/3]
			fxch st(2)
			fsub st(0), st(3)
			fxch st(2)
			; AKTUALNA ZAWARTOSC STOSU: [x, y, kąt - PI/3, PI/3]
			jmp gK_loop			; kontynuuj bieganie po znakach 
		
		gK_exit:
			popa 
			ret
	generate_Koch endp 

	; === 5a. PRZESUN ZOLWIA ===
	; przesuwa zolwia o len pixeli zgodnie z aktualnym kierunkiem, rysujac nasza krzywa 
	move_turtle proc
		; wejscie: [x, y, kąt, PI/3]	
		pusha 
		
		mov bl, byte ptr ds:[len]
		xor bh, bh
		mov di, bx 						; dlugosc odcinka pokonywanego przez zolwia -> di
 
		; oblicz sinus i cosinus naszego kąta 
		fld st(2)						; zrob kopie kąta : st(0) = kąt 
										; AKTUALNA ZAWARTOSC STOSU: [kąt, x, y, kąt, PI/3]
		fld st(0)						; AKTUALNA ZAWARTOSC STOSU: [kąt, kąt, x, y, kąt, PI/3]
		fsin							; st(0) := sinus [st(0)] - AKTUALNA ZAWARTOSC STOSU: [sin(kąt), kąt, x, y, kąt, PI/3] // moze byc tez fsincos
		fxch st(1)						; AKTUALNA ZAWARTOSC STOSU: [kąt, sin(kąt), x, y, kąt, PI/3]
		fcos							; AKTUALNA ZAWARTOSC STOSU: [cos(kąt), sin(kąt), x, y, kąt, PI/3]
		
		fincstp							; zwiększ wskaźnik stosu o 2 - przesuń st(5) na st(3), st(4) na st(2) itd. (o 2 "w lewo")
		fincstp							
		
		; AKTUALNA ZAWARTOSC STOSU:
		; [x, y, kąt, PI/3, _,  _, cos(kąt), sin(kąt)]
 
		draw_section:
			cmp di, 0h						; czy narysowano już "len" pixeli?
			jz mt_finish					; jesli tak, konczymy 
			; jnz:
			fadd st(0), st(6) 				; st(0) = st(0) + cos(kąt)
			fist word ptr ds:[intx] 		; wyliczony wlasnie x zapisz do zmiennej "intx"
		 
			fxch st(1) 						; zamien st(0) i st(1) miejscami
											; AKTUALNA ZAWARTOSC STOSU: [y, x, kąt, PI/3, _, _, cos(kąt), sin(kąt)]
		 
			fadd st(0), st(7) 				; st(0) = st(0) + sin(kąt)
			fist word ptr ds:[inty] 		; wyliczony wlasnie y zapisz do zmiennej "inty"
		 
			fwait 							; czekaj, aż FPU skończy pracę, używane do synchronizacji z CPU
			fxch st(1) 						; naprawiamy - zamien st(0) i st(1) miejscami
											; AKTUALNA ZAWARTOSC STOSU: [x, y, kąt, PI/3, _, _, cos(kąt), sin(kąt)]

			mov cx, word ptr ds:[intx]		; wspolrzedne -> rejestry, bedziemy rysowac zaraz 
			mov dx, word ptr ds:[inty]
			
			; nie wychodzimy poza ekran 
			cmp cx, 319
			ja continue
			cmp dx, 199
			ja continue
		 
			mov al, 14d					; al - kolor pixela, (x, y) = (cx, dx)
			mov ah, 0ch					; kod funkcji - rysuj pixel 
			int 10h 					; przerwanie 10h z funkcja 0ch 
			
			continue:
			dec di
			jmp draw_section
			
		mt_finish:
			ffree st(7) 				; zwolnij st(7)
			ffree st(6) 				; zwolnij st(6)
		
		; wyjscie: AKTUALNA ZAWARTOSC STOSU: [x, y, kąt, PI/3]
		popa
		ret 
	move_turtle endp
	
	; === ZAKONCZ PROGRAM ===
	end_of_prog proc
			mov	ah, 4ch			; koniec, powrot do DOS - int 21,4c -> terminate process
			int	21h
			ret
	end_of_prog endp 

code ends

stack segment stack
	dw 150 dup (?)				
	stack_ptr dw ?
stack ends

end start
