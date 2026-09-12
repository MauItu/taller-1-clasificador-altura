(* ==========================================================================
   Clasificador de cajas por altura  -  Taller 1
   Programa de control IEC 61131-3 (Texto Estructurado)

   ENTRADAS   tres fotocelulas difusas de la escena
   SALIDA     comando de extension del desviador

   La estacion de medicion determina si la caja supera la altura de corte.
   El veredicto viaja en un registro de desplazamiento (FIFO) hasta que la
   caja llega al desviador, de modo que la clasificacion no depende de la
   velocidad de la cinta ni de temporizadores calibrados.
   ========================================================================== *)

VAR_INPUT
    GatePresence : BOOL;    (* haz bajo  - lo corta toda caja       *)
    GateHeight   : BOOL;    (* haz alto  - solo lo cortan las altas *)
    DivertEye    : BOOL;    (* fotocelula de disparo del desviador  *)
END_VAR

VAR_OUTPUT
    DivertCmd : BOOL;       (* TRUE = paleta extendida *)
END_VAR

VAR
    GateRise  : R_TRIG;     (* flanco: entra caja a la estacion *)
    GateFall  : F_TRIG;     (* flanco: sale caja de la estacion *)
    EyeRise   : R_TRIG;     (* flanco: llega caja al desviador  *)
    PushTimer : TON;        (* duracion del empuje              *)

    TallLatch : BOOL;                   (* la caja actual corto el haz alto *)
    Armed     : BOOL;                   (* hay una caja en curso en la estacion *)
    Fifo      : ARRAY [0..7] OF BOOL;   (* registro de desplazamiento       *)
    Pending   : INT;                    (* veredictos en transito           *)
    Verdict   : BOOL;                   (* veredicto desencolado este scan  *)
    i         : INT;

    Counted   : INT;        (* estadisticas para el monitor ST *)
    Diverted  : INT;
    Passed    : INT;
END_VAR


(* ---------- deteccion de flancos ---------- *)
GateRise(CLK := GatePresence);
GateFall(CLK := GatePresence);
EyeRise(CLK := DivertEye);


(* ---------- ESTACION DE MEDICION ----------
   El veredicto se acumula durante toda la ventana en que la caja esta
   frente a la estacion: basta con que corte el haz alto en algun instante
   para marcarla como alta. Eso la hace inmune a rebotes de la caja. *)

IF GateRise.Q THEN
    TallLatch := FALSE;
    Armed := TRUE;
END_IF;

IF GatePresence AND GateHeight THEN
    TallLatch := TRUE;
END_IF;

(* La caja termino de pasar: el veredicto entra al final de la cola.
   La guarda 'Armed' exige haber visto antes el flanco de entrada. Sin ella, el
   F_TRIG de este runtime emite un flanco de bajada espurio en el primer scan
   (su estado interno arranca en TRUE) y encolaria un veredicto fantasma, que
   correria toda la cola una posicion de forma permanente. *)
IF GateFall.Q AND Armed THEN
    Armed := FALSE;
    IF Pending < 8 THEN
        Fifo[Pending] := TallLatch;
        Pending := Pending + 1;
        Counted := Counted + 1;
    END_IF;
END_IF;


(* ---------- DESVIADOR ----------
   Al llegar una caja se desencola el veredicto mas viejo. Como las cajas no
   se adelantan entre si en la cinta, ese veredicto es siempre el suyo. *)

Verdict := FALSE;

IF EyeRise.Q THEN
    IF Pending > 0 THEN
        Verdict := Fifo[0];
        FOR i := 0 TO 6 DO
            Fifo[i] := Fifo[i + 1];
        END_FOR;
        Pending := Pending - 1;
        IF Verdict THEN
            Diverted := Diverted + 1;
        ELSE
            Passed := Passed + 1;
        END_IF;
    END_IF;
END_IF;


(* ---------- ACTUADOR ----------
   La paleta sale al desencolar una caja alta y se retrae sola por tiempo. *)

PushTimer(IN := DivertCmd, PT := T#1100ms);

IF Verdict THEN
    DivertCmd := TRUE;
ELSIF PushTimer.Q THEN
    DivertCmd := FALSE;
END_IF;
