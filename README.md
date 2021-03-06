# net_calc

1.  Сервер, который умеет на вход принимать пачку примеров разбивать её на необходимое количество процессов,
    каждый из которых обрабатывает полученные задания и записывает результат в файл.
    После получения списка примеров, сервер должен отдать номер задания.
    По номеру задания сервер должен уметь возвращать статус выполнения этого задания:
    - `new` - задание в очереди (время нахождения в этом статусе)
    - `work` - задание в процессе обработки (время нахождения в этом статусе)
    - `error` - задание невозможно выполнить (ошибка выполнения)
    - `done` - задание выполнено (результирующий файл)
2.  Клиент генерирует задания для расчета, устанавливает соединение к серверу,
    передаёт сгенерированные примеры, получает id задания в ответ.
    Так же должен уметь запросить у сервера статус выполнения,
    сохранить результирующий файл на диск и отдать путь к файлу.
    
**Важно!**
1.  Сервер при запуске должен обрабатывать аргументы:
    - количество одновременно обрабатываемых заданий,
    - количество процессов для каждого задания,
    - максимальный размер очереди на обработку.
2.  Все форки в рамках одного задания должны писать результат в один файл.
3.  Передача файла от сервера к клиенту должна проходить через gzip, сервер архивирует (gzip) файл, 
    передаёт на клиент, клиент разорхивирует поток и записывает в файл.
4.  Если хоть один обработчик завершил свою работу с сигналом отличным от 0,
    необходимо прервать работу всех остальных, сохранить ошибку и выставить статус.
5.  После передачи файла клиенту он должен быть удален с диска.
    
